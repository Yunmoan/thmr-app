#include "linux_tray.h"

#include <gio/gio.h>
#include <cstring>

namespace {
void respond(FlMethodCall* call, bool available) {
  g_autoptr(FlValue) value = fl_value_new_bool(available);
  fl_method_call_respond_success(call, value, nullptr);
  g_object_unref(call);
}

void property_received(GObject* source, GAsyncResult* result, gpointer data) {
  auto* call = FL_METHOD_CALL(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), result, &error);
  bool available = false;
  if (reply != nullptr) {
    g_autoptr(GVariant) boxed = g_variant_get_child_value(reply, 0);
    g_autoptr(GVariant) value = g_variant_get_variant(boxed);
    available = g_variant_is_of_type(value, G_VARIANT_TYPE_BOOLEAN) &&
                g_variant_get_boolean(value);
  }
  respond(call, available);
}

void bus_received(GObject*, GAsyncResult* result, gpointer data) {
  auto* call = FL_METHOD_CALL(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus = g_bus_get_finish(result, &error);
  if (bus == nullptr) {
    respond(call, false);
    return;
  }
  // A watcher may exist without a panel hosting its items (notably GNOME).
  // Successful app_indicator_new() alone does not mean the icon is usable.
  g_dbus_connection_call(
      bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", "org.kde.StatusNotifierWatcher",
                    "IsStatusNotifierHostRegistered"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1000, nullptr,
      property_received, call);
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (strcmp(fl_method_call_get_name(call), "isAvailable") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  g_bus_get(G_BUS_TYPE_SESSION, nullptr, bus_received, g_object_ref(call));
}
}  // namespace

void register_linux_tray(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "thmr/linux_tray",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call, nullptr,
                                           nullptr);
}
