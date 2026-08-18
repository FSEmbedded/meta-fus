/* SPDX-License-Identifier: LGPL-2.1-only
 *
 * contract test driver for the fs-updater exec backend of rauc_install().
 * one rauc_install() per process, mirroring the daemon's lifecycle.
 *
 * modes:
 *   (default)      no status consumer -- exercises the
 *                  drop-when-unconsumed guard
 *   --with-notify  draining status consumer -- exercises the queue path
 *   --with-auth    auth header -- the backend must refuse (streaming
 *                  cannot be delegated to a local-path installer)
 *
 * exit: 0 if rauc_install() reported success, 1 if failure.
 */
#include <glib.h>
#include <string.h>
#include "rauc-installer.h"

static gboolean drain_status(gpointer data)
{
	struct install_context *context = data;
	gchar *msg;

	g_mutex_lock(&context->status_mutex);
	while ((msg = g_queue_pop_head(&context->status_messages)))
		g_free(msg);
	g_mutex_unlock(&context->status_mutex);

	return G_SOURCE_REMOVE;
}

int main(int argc, char **argv)
{
	const gchar *auth = NULL;
	GSourceFunc notify = NULL;

	if (argc > 1 && strcmp(argv[1], "--with-auth") == 0)
		auth = "Authorization: TargetToken test";
	if (argc > 1 && strcmp(argv[1], "--with-notify") == 0)
		notify = drain_status;

	return rauc_install("/dev/null", auth, TRUE, notify, NULL, TRUE) ? 0 : 1;
}
