#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// 为进程创建控制台，将 runner 和 Flutter 库的 stdout 与 stderr 重定向到该控制台。
void CreateAndAttachConsole();

// 将空字符结尾的 UTF-16 wchar_t 字符串转为 UTF-8 std::string，失败时返回空字符串。
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// 获取以 UTF-8 编码的命令行参数，返回 std::vector<std::string>。失败时返回空向量。
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
