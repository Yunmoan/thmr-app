import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/radio_api.dart';
import '../../../core/state/radio_source_provider.dart';
import '../../../core/config.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/thmr_theme.dart';

/// 反馈类型(7.3 枚举)。
const _feedbackTypes = <(String, String)>[
  ('non-touhou', '非东方歌曲'),
  ('non-music', '非音乐节目'),
  ('copyright', '版权投诉'),
  ('copyright-takedown', '下架请求'),
  ('copyright-attribution', '版权信息错误'),
  ('copyright-permission', '授权 / 来源补充'),
  ('violation', '违规反馈'),
  ('metadata', '曲目信息错误'),
  ('playback', '播放异常'),
  ('other', '其他'),
];

/// 曲目反馈表单(对齐 Web 端 FeedbackDialog)。
Future<void> showFeedbackSheet(
  BuildContext context, {
  required TrackRef track,
  String? stationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _FeedbackForm(
        track: track,
        stationId: stationId?.trim().isNotEmpty == true
            ? stationId!.trim()
            : appConfig.stationId,
      ),
    ),
  );
}

class _FeedbackForm extends ConsumerStatefulWidget {
  const _FeedbackForm({required this.track, required this.stationId});

  final TrackRef track;
  final String stationId;

  @override
  ConsumerState<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<_FeedbackForm> {
  String _type = 'metadata';
  final _contact = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  static const _contactKey = 'last_feedback_contact';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getString(_contactKey);
      if (mounted && v != null && v.isNotEmpty && _contact.text.isEmpty) {
        setState(() => _contact.text = v);
      }
    });
  }

  @override
  void dispose() {
    _contact.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_contact.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写联系方式')));
      return;
    }
    setState(() => _busy = true);
    try {
      final radio = ref.read(radioApiProvider);
      final result = await radio.feedback(
        stationId: widget.stationId,
        type: _type,
        contact: _contact.text.trim(),
        message: _message.text.trim(),
        track: widget.track,
      );
      await SharedPreferences.getInstance()
          .then((p) => p.setString(_contactKey, _contact.text.trim()));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.autoSkipped
            ? '感谢反馈!该曲目已累积多次异常反馈,已为你切换曲目'
            : '反馈已提交,感谢守护幻想乡的放送质量'),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('提交失败:${e.message}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('网络异常,稍后再试')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('曲目反馈',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '正在反馈:${widget.track.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.mutedInk),
            ),
            const SizedBox(height: 16),
            Text('反馈类型',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, label) in _feedbackTypes)
                  ChoiceChip(
                    label: Text(label),
                    selected: _type == value,
                    onSelected: (_) => setState(() => _type = value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contact,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '联系方式(必填)',
                hintText: '邮箱 / QQ 等,便于回访',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '补充说明(可选)',
                hintText: '例如:曲名/艺术家信息有误、音质异常…',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('提交反馈'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
