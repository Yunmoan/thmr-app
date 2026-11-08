#include <dlfcn.h>
#include <cstdio>

int main() {
  const char* names[] = {"libmpv.so.2", "libmpv.so.1", "libmpv.so"};
  for (const char* name : names) {
    void* library = dlopen(name, RTLD_NOW | RTLD_LOCAL);
    if (library != nullptr) {
      dlclose(library);
      return 0;
    }
  }
  std::fputs("THMR: libmpv or one of its dependencies is unavailable.\n"
             "缺少播放运行库，请先安装：\n"
             "  Debian/Ubuntu: sudo apt install libmpv2\n"
             "  Arch Linux:    sudo pacman -S mpv\n"
             "See README-Linux.md for the complete runtime dependencies.\n",
             stderr);
  return 1;
}
