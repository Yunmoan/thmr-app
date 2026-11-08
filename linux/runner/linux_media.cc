#include "linux_media.h"
#include "mpris_service.h"

#include <cstring>
#include <memory>

namespace {
struct Bridge {
  FlMethodChannel* channel;
  std::unique_ptr<MprisService> service;
};
std::string text(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value) : "";
}
gint64 number(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? fl_value_get_int(value) : 0;
}
void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* bridge = static_cast<Bridge*>(data);
  const char* method = fl_method_call_get_name(call);
  if (strcmp(method, "start") == 0) {
    if (!bridge->service) {
      bridge->service.reset(new MprisService([bridge](const char* command,
                                                      double value) {
        g_autoptr(FlValue) args = fl_value_new_map();
        fl_value_set_string_take(args, "command", fl_value_new_string(command));
        fl_value_set_string_take(args, "value", fl_value_new_float(value));
        fl_method_channel_invoke_method(bridge->channel, "command", args,
                                         nullptr, nullptr, nullptr);
      }));
    }
  } else if (strcmp(method, "stop") == 0) {
    bridge->service.reset();
  } else if (strcmp(method, "update") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_error(call, "invalid_args", "Expected media state",
                                   nullptr, nullptr);
      return;
    }
    if (bridge->service) {
      FlValue* volume = fl_value_lookup_string(args, "volume");
      bridge->service->Update(
          text(args, "status"), text(args, "track"), text(args, "title"),
          text(args, "artist"), text(args, "artwork"), number(args, "duration"),
          number(args, "position"),
          volume && fl_value_get_type(volume) == FL_VALUE_TYPE_FLOAT
              ? fl_value_get_float(volume) : 1);
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}
}  // namespace

void register_linux_media(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "thmr/linux_media",
      FL_METHOD_CODEC(codec));
  auto* bridge = new Bridge{channel, nullptr};
  fl_method_channel_set_method_call_handler(
      channel, method_call, bridge,
      [](gpointer data) { delete static_cast<Bridge*>(data); });
}
