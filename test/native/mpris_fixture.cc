#include "mpris_service.h"
#include <glib-unix.h>
#include <csignal>
#include <iostream>
#include <memory>

int main() {
  GMainLoop* loop = g_main_loop_new(nullptr, false);
  std::string status = "Stopped";
  double volume = 1;
  std::unique_ptr<MprisService> service;
  auto update = [&]() {
    service->Update(status, "track/42-123", "Test song", "Test artist",
                    "https://example.test/cover.png", 20000000, 5000000, volume);
  };
  service.reset(new MprisService([&](const char* command, double value) {
    const std::string name(command);
    if (name == "play") status = "Playing";
    if (name == "pause") status = "Paused";
    if (name == "stop") status = "Stopped";
    if (name == "volume") volume = value;
    if (name == "raise") std::cout << "raised" << std::endl;
    update();
  }));
  update();
  g_unix_signal_add(SIGTERM, [](gpointer data) -> gboolean {
    g_main_loop_quit(static_cast<GMainLoop*>(data));
    return G_SOURCE_REMOVE;
  }, loop);
  g_main_loop_run(loop);
  service.reset();
  g_main_loop_unref(loop);
}
