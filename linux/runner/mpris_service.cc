#include "mpris_service.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <utility>

namespace {
constexpr char kRoot[] = "org.mpris.MediaPlayer2";
constexpr char kPlayer[] = "org.mpris.MediaPlayer2.Player";
constexpr char kPath[] = "/org/mpris/MediaPlayer2";
constexpr char kXml[] = R"XML(
<node>
 <interface name="org.mpris.MediaPlayer2">
  <method name="Raise"/><method name="Quit"/>
  <property name="CanQuit" type="b" access="read"/>
  <property name="CanRaise" type="b" access="read"/>
  <property name="HasTrackList" type="b" access="read"/>
  <property name="Identity" type="s" access="read"/>
  <property name="DesktopEntry" type="s" access="read"/>
  <property name="SupportedUriSchemes" type="as" access="read"/>
  <property name="SupportedMimeTypes" type="as" access="read"/>
 </interface>
 <interface name="org.mpris.MediaPlayer2.Player">
  <method name="Play"/><method name="Pause"/><method name="PlayPause"/>
  <method name="Stop"/><method name="Next"/><method name="Previous"/>
  <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
  <method name="SetPosition"><arg name="TrackId" type="o" direction="in"/>
   <arg name="Position" type="x" direction="in"/></method>
  <method name="OpenUri"><arg name="Uri" type="s" direction="in"/></method>
  <signal name="Seeked"><arg name="Position" type="x"/></signal>
  <property name="PlaybackStatus" type="s" access="read"/>
  <property name="Rate" type="d" access="readwrite"/>
  <property name="Metadata" type="a{sv}" access="read"/>
  <property name="Volume" type="d" access="readwrite"/>
  <property name="Position" type="x" access="read"/>
  <property name="MinimumRate" type="d" access="read"/>
  <property name="MaximumRate" type="d" access="read"/>
  <property name="CanGoNext" type="b" access="read"/>
  <property name="CanGoPrevious" type="b" access="read"/>
  <property name="CanPlay" type="b" access="read"/>
  <property name="CanPause" type="b" access="read"/>
  <property name="CanSeek" type="b" access="read"/>
  <property name="CanControl" type="b" access="read"/>
 </interface>
</node>)XML";
const GDBusInterfaceVTable kVtable = {
    [](GDBusConnection*, const gchar*, const gchar*, const gchar* interface,
       const gchar* method, GVariant*, GDBusMethodInvocation* invocation,
       gpointer data) {
      static_cast<MprisService*>(data)->Method(interface, method, invocation);
    },
    [](GDBusConnection*, const gchar*, const gchar*, const gchar* interface,
       const gchar* property, GError**, gpointer data) -> GVariant* {
      return static_cast<MprisService*>(data)->Property(interface, property);
    },
    [](GDBusConnection*, const gchar*, const gchar*, const gchar*,
       const gchar* property, GVariant* value, GError** error,
       gpointer data) -> gboolean {
      return static_cast<MprisService*>(data)->Set(property, value, error);
    },
    {nullptr}};
}  // namespace

MprisService::MprisService(Command command) : command_(std::move(command)) {
  node_ = g_dbus_node_info_new_for_xml(kXml, nullptr);
  metadata_ = g_variant_ref_sink(g_variant_new_array(G_VARIANT_TYPE("{sv}"),
                                                    nullptr, 0));
  owner_ = g_bus_own_name(G_BUS_TYPE_SESSION, "org.mpris.MediaPlayer2.thmr",
                         G_BUS_NAME_OWNER_FLAGS_DO_NOT_QUEUE, BusAcquired,
                         nullptr, nullptr, this, nullptr);
}

MprisService::~MprisService() {
  g_bus_unown_name(owner_);
  ReleaseBus();
  g_variant_unref(metadata_);
  g_dbus_node_info_unref(node_);
}

void MprisService::ReleaseBus() {
  if (bus_ == nullptr) return;
  for (auto& registration : registrations_) {
    if (registration != 0) g_dbus_connection_unregister_object(bus_, registration);
    registration = 0;
  }
  g_clear_object(&bus_);
}

void MprisService::BusAcquired(GDBusConnection* bus, const gchar*, gpointer data) {
  auto* self = static_cast<MprisService*>(data);
  self->ReleaseBus();
  self->bus_ = G_DBUS_CONNECTION(g_object_ref(bus));
  for (int i = 0; i < 2; ++i) {
    g_autoptr(GError) error = nullptr;
    self->registrations_[i] = g_dbus_connection_register_object(
        bus, kPath, self->node_->interfaces[i], &kVtable, self, nullptr, &error);
    if (error != nullptr) g_warning("MPRIS registration: %s", error->message);
  }
}

GVariant* MprisService::Property(const char* interface, const char* name) const {
  if (strcmp(interface, kRoot) == 0) {
    if (strcmp(name, "Identity") == 0)
      return g_variant_new_string("东方音乐电台 THMR");
    if (strcmp(name, "DesktopEntry") == 0)
      return g_variant_new_string("cn.yunmoan.thmr.thmr_app");
    if (strcmp(name, "SupportedUriSchemes") == 0 ||
        strcmp(name, "SupportedMimeTypes") == 0)
      return g_variant_new_strv(nullptr, 0);
    return g_variant_new_boolean(strcmp(name, "CanRaise") == 0);
  }
  if (strcmp(name, "PlaybackStatus") == 0)
    return g_variant_new_string(status_.c_str());
  if (strcmp(name, "Metadata") == 0) return g_variant_ref(metadata_);
  if (strcmp(name, "Volume") == 0) return g_variant_new_double(volume_);
  if (strcmp(name, "Position") == 0) {
    gint64 position = position_;
    if (status_ == "Playing") position += g_get_monotonic_time() - position_time_;
    if (duration_ > 0) position = std::min(position, duration_);
    return g_variant_new_int64(position);
  }
  if (strcmp(name, "Rate") == 0 || strcmp(name, "MinimumRate") == 0 ||
      strcmp(name, "MaximumRate") == 0)
    return g_variant_new_double(1);
  return g_variant_new_boolean(strcmp(name, "CanPlay") == 0 ||
                               strcmp(name, "CanPause") == 0 ||
                               strcmp(name, "CanControl") == 0);
}

void MprisService::Method(const char* interface, const char* name,
                          GDBusMethodInvocation* invocation) {
  if (strcmp(interface, kRoot) == 0) {
    if (strcmp(name, "Raise") == 0) command_("raise", 0);
  } else if (strcmp(name, "Play") == 0) {
    command_("play", 0);
  } else if (strcmp(name, "Pause") == 0) {
    command_("pause", 0);
  } else if (strcmp(name, "Stop") == 0) {
    command_("stop", 0);
  } else if (strcmp(name, "PlayPause") == 0) {
    command_(status_ == "Playing" ? "pause" : "play", 0);
  } else if (strcmp(name, "OpenUri") == 0) {
    g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                          G_DBUS_ERROR_NOT_SUPPORTED,
                                          "This player only plays live radio");
    return;
  }
  // Seeking, track navigation and Quit have no effect, as advertised.
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

gboolean MprisService::Set(const char* name, GVariant* value, GError** error) {
  const double number = g_variant_get_double(value);
  if (!std::isfinite(number)) {
    g_set_error_literal(error, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS,
                        "Expected a finite value");
    return false;
  }
  if (strcmp(name, "Volume") == 0) {
    command_("volume", std::max(0.0, std::min(1.0, number)));
    return true;
  }
  if (strcmp(name, "Rate") == 0 && number == 1) return true;
  g_set_error_literal(error, G_DBUS_ERROR, G_DBUS_ERROR_NOT_SUPPORTED,
                      "Live radio uses a fixed playback rate");
  return false;
}

void MprisService::Changed(const char* name, GVariant* value) {
  g_autoptr(GVariant) owned = g_variant_ref_sink(value);
  if (bus_ == nullptr) return;
  GVariantBuilder changed;
  g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&changed, "{sv}", name, value);
  g_dbus_connection_emit_signal(
      bus_, nullptr, kPath, "org.freedesktop.DBus.Properties", "PropertiesChanged",
      g_variant_new("(sa{sv}as)", kPlayer, &changed, nullptr), nullptr);
}

void MprisService::Update(const std::string& status, const std::string& track,
                           const std::string& title, const std::string& artist,
                           const std::string& artwork, gint64 duration,
                           gint64 position, double volume) {
  if (status != status_) {
    status_ = status;
    Changed("PlaybackStatus", g_variant_new_string(status_.c_str()));
  }
  if (volume != volume_) {
    volume_ = volume;
    Changed("Volume", g_variant_new_double(volume_));
  }
  duration_ = std::max<gint64>(0, duration);
  position_ = std::max<gint64>(0, position);
  position_time_ = g_get_monotonic_time();
  GVariantBuilder metadata;
  g_variant_builder_init(&metadata, G_VARIANT_TYPE("a{sv}"));
  if (!track.empty()) {
    g_autofree gchar* hash = g_compute_checksum_for_string(
        G_CHECKSUM_SHA256, track.c_str(), -1);
    const std::string path = std::string(kPath) + "/track/" + hash;
    g_variant_builder_add(&metadata, "{sv}", "mpris:trackid",
                          g_variant_new_object_path(path.c_str()));
    g_variant_builder_add(&metadata, "{sv}", "xesam:title",
                          g_variant_new_string(title.c_str()));
    const gchar* artists[] = {artist.c_str(), nullptr};
    g_variant_builder_add(&metadata, "{sv}", "xesam:artist",
                          g_variant_new_strv(artists, -1));
    g_variant_builder_add(&metadata, "{sv}", "mpris:length",
                          g_variant_new_int64(duration_));
    if (!artwork.empty())
      g_variant_builder_add(&metadata, "{sv}", "mpris:artUrl",
                            g_variant_new_string(artwork.c_str()));
  }
  GVariant* next = g_variant_ref_sink(g_variant_builder_end(&metadata));
  if (!g_variant_equal(metadata_, next)) {
    g_variant_unref(metadata_);
    metadata_ = next;
    Changed("Metadata", metadata_);
  } else {
    g_variant_unref(next);
  }
}
