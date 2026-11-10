resource "open77_contextmenu"
version "1.2.0"
open77_version ">=0.0.1"
auto_start true
reload_policy "reconnect"
client_scripts { "shared/config.lua", "client/registry.lua", "client/ui.lua", "client/main.lua" }
-- The menu is a NativeUI document (since 1.2.0; it was a WebUI page before).
files { "ui/contextmenu.rml", "ui/contextmenu.rcss" }
permissions { "world.query", "input.actions", "players.controls", "local.events" }
