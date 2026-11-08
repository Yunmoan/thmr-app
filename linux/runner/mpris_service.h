#ifndef RUNNER_MPRIS_SERVICE_H_
#define RUNNER_MPRIS_SERVICE_H_

#include <gio/gio.h>
#include <functional>
#include <string>

// Owns the session-bus registration; independent of Flutter for integration tests.
class MprisService {
 public:
  using Command = std::function<void(const char*, double)>;
  explicit MprisService(Command command);
  ~MprisService();
  void Update(const std::string& status, const std::string& track,
              const std::string& title, const std::string& artist,
              const std::string& artwork, gint64 duration, gint64 position,
              double volume);
  GVariant* Property(const char* interface, const char* name) const;
  void Method(const char* interface, const char* name,
              GDBusMethodInvocation* invocation);
  gboolean Set(const char* name, GVariant* value, GError** error);

 private:
  static void BusAcquired(GDBusConnection*, const gchar*, gpointer);
  void ReleaseBus();
  void Changed(const char* name, GVariant* value);
  Command command_;
  guint owner_ = 0;
  GDBusConnection* bus_ = nullptr;
  GDBusNodeInfo* node_ = nullptr;
  guint registrations_[2] = {0, 0};
  GVariant* metadata_ = nullptr;
  std::string status_ = "Stopped";
  gint64 position_ = 0;
  gint64 duration_ = 0;
  gint64 position_time_ = 0;
  double volume_ = 1;
};
#endif
