#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <locale.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "linux_tray.h"
#include "linux_media.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gboolean first_frame_received;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// 收到 Flutter 首帧后调用，显示 GTK 窗口。
static void first_frame_cb(MyApplication* self, FlView* view) {
  self->first_frame_received = TRUE;
  gtk_window_present(GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view))));
}

// 实现 GApplication::activate。
static void my_application_activate(GApplication* application) {
  // libmpv 的 mpv_create() 要求 LC_NUMERIC 为 "C"。在 GTK 初始化后、Flutter 引擎启动前设定数值
  // 区域，避免 zh_CN 等区域导致播放器初始化失败。
  setlocale(LC_NUMERIC, "C");

  MyApplication* self = MY_APPLICATION(application);
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    // GApplication 将后续启动请求转给已有进程。当首帧已就绪时，重新显示最小化或隐藏的窗口。
    if (self->first_frame_received) gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // GNOME Shell 与 Wayland 默认使用 GTK HeaderBar。X11 下的其他窗口管理器沿用系统标题栏，
  // 以适配平铺等布局。
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "东方音乐电台 THMR");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "东方音乐电台 THMR");
  }

  gtk_window_set_default_size(window, 1180, 780);
  GdkGeometry geometry = {};
  geometry.min_width = 430;
  geometry.min_height = 660;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Flutter 视图在首帧前使用黑色底色。
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // 先将视图实例化为原生组件以启动绘制，收到 Flutter 首帧后再显示窗口。
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  register_linux_tray(view);
  register_linux_media(view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// 实现 GApplication::local_command_line。
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // 跳过表示可执行文件路径的首个参数。
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// 实现 GApplication::startup。
static void my_application_startup(GApplication* application) {


  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// 实现 GApplication::shutdown。
static void my_application_shutdown(GApplication* application) {


  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// 实现 GObject::dispose。
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // 以应用 ID 作为进程名，便于 GTK 和桌面环境按应用 ID 关联对应的 .desktop 入口。
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     static_cast<GApplicationFlags>(0), nullptr));
}
