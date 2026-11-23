#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication,
                     my_application,
                     MY,
                     APPLICATION,
                     GtkApplication)

/**
 * my_application_new:
 *
 * 创建基于 Flutter 的 GTK 应用。
 *
 * Returns: 新建的 #MyApplication。
 */
MyApplication* my_application_new();

#endif  // FLUTTER_MY_APPLICATION_H_
