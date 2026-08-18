/**
 * SPDX-License-Identifier: LGPL-2.1-only
 *
 * fs-updater backend for rauc-hawkbit-updater (meta-fus container mode).
 *
 * Replaces the stock de.pengutronix.rauc D-Bus proxy: every install is
 * delegated to `fs-updater --install_update <bundle>` so fs-updater-lib
 * stays the sole update/state actor (manifest-based fw/app routing,
 * verity-sidecar activation, U-Boot state). rauc_install()'s threading,
 * callback and context-lifetime contract is byte-compatible with the
 * stock implementation in rauc-installer.c.
 */
#include <glib.h>
#include <sys/wait.h>
#include "rauc-installer.h"

#ifndef FSUPDATER_CLI
#define FSUPDATER_CLI "/usr/sbin/fs-updater"
#endif

static GThread *thread_install = NULL;

static struct install_context *install_context_new(void)
{
	struct install_context *context = g_new0(struct install_context, 1);

	g_mutex_init(&context->status_mutex);
	g_queue_init(&context->status_messages);
	context->status_result = -2;

	return context;
}

static void install_context_free(struct install_context *context)
{
	if (!context)
		return;

	g_free(context->bundle);
	g_free(context->auth_header);
	g_mutex_clear(&context->status_mutex);

	while (g_main_context_iteration(context->loop_context, FALSE));
	g_main_context_unref(context->loop_context);

	g_assert_cmpint(context->status_result, >=, 0);
	g_assert_true(g_queue_is_empty(&context->status_messages));
	g_main_loop_unref(context->mainloop);
	g_free(context);
}

static void push_status(struct install_context *context, gchar *msg)
{
	/* mirrors upstream's notify-consumer guard: with no consumer, drop
	 * the message -- an unconsumed queue would trip
	 * install_context_free()'s g_queue_is_empty() assertion. */
	if (!context->notify_event) {
		g_free(msg);
		return;
	}

	g_mutex_lock(&context->status_mutex);
	g_queue_push_tail(&context->status_messages, msg);
	g_mutex_unlock(&context->status_mutex);

	g_main_context_invoke(context->loop_context, context->notify_event, context);
}

static gpointer install_loop_thread(gpointer data)
{
	struct install_context *context = NULL;
	g_autoptr(GError) error = NULL;
	gint wait_status = 0;
	gint exit_code = -1;
	gint result = 1;
	gchar *argv[4] = {FSUPDATER_CLI, "--install_update", NULL, NULL};

	g_return_val_if_fail(data, NULL);

	context = data;
	argv[2] = context->bundle;
	g_main_context_push_thread_default(context->loop_context);

	if (context->auth_header) {
		/* stream_bundle=true cannot be honoured: fs-updater installs
		 * from a local path. fail loudly instead of silently
		 * bypassing the orchestrator. */
		push_status(context, g_strdup(
			"fs-updater backend does not support stream_bundle; "
			"set stream_bundle=false"));
		goto out;
	}

	push_status(context, g_strdup_printf("delegating to %s --install_update %s",
					     FSUPDATER_CLI, context->bundle));

	if (!g_spawn_sync(NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL,
			  NULL, NULL, &wait_status, &error)) {
		push_status(context, g_strdup_printf("failed to spawn fs-updater: %s",
						     error->message));
		goto out;
	}

	if (!WIFEXITED(wait_status)) {
		push_status(context, g_strdup_printf(
			"fs-updater terminated abnormally (wait status %d)", wait_status));
		goto out;
	}

	/* fs-updater's exit codes are type-encoded, not a 0/1 boolean
	 * (fs_updater_error.h): firmware success = 0, application = 4,
	 * combined = 8, untyped raw bundle = 48 -- a hawkBit-delivered
	 * .raucb is untyped, so "any nonzero is failure" would misreport
	 * every successful install here. 47 means the CLI's no-progress
	 * watchdog gave up while the install continued; report failure but
	 * note it distinctly. */
	exit_code = WEXITSTATUS(wait_status);
	switch (exit_code) {
	case 0:
	case 4:
	case 8:
	case 48:
		push_status(context, g_strdup_printf(
			"fs-updater --install_update succeeded (exit %d)", exit_code));
		result = 0;
		break;
	case 47:
		push_status(context, g_strdup(
			"fs-updater install still running past the CLI's no-progress "
			"watchdog; reporting failure (raise FSUP_INSTALL_WAIT_MS)"));
		break;
	default:
		push_status(context, g_strdup_printf(
			"fs-updater --install_update failed (exit %d)", exit_code));
		break;
	}

out:
	g_mutex_lock(&context->status_mutex);
	context->status_result = result;
	g_mutex_unlock(&context->status_mutex);

	if (context->notify_complete)
		context->notify_complete(context);

	g_main_context_pop_thread_default(context->loop_context);

	if (!context->keep_install_context)
		install_context_free(context);
	return NULL;
}

gboolean rauc_install(const gchar *bundle, const gchar *auth_header, gboolean ssl_verify,
		      GSourceFunc on_install_notify, GSourceFunc on_install_complete,
		      gboolean wait)
{
	GMainContext *loop_context = NULL;
	struct install_context *context = NULL;

	g_return_val_if_fail(bundle, FALSE);

	loop_context = g_main_context_new();
	context = install_context_new();
	context->bundle = g_strdup(bundle);
	context->auth_header = g_strdup(auth_header);
	context->ssl_verify = ssl_verify;
	context->notify_event = on_install_notify;
	context->notify_complete = on_install_complete;
	context->mainloop = g_main_loop_new(loop_context, FALSE);
	context->loop_context = loop_context;
	context->status_result = 2;
	context->keep_install_context = wait;

	if (thread_install)
		g_thread_join(thread_install);

	thread_install = g_thread_new("installer", install_loop_thread, (gpointer) context);
	if (wait) {
		gboolean result;

		g_thread_join(thread_install);
		result = context->status_result == 0;

		install_context_free(context);
		return result;
	}

	return TRUE;
}
