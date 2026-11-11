import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/radio_api.dart';
import '../../../core/models/models.dart';
import '../../../core/state/app_providers.dart';
import '../../../core/state/auth_provider.dart';
import '../../../core/state/channel_provider.dart';
import '../../../core/state/station_provider.dart';
import '../../../core/theme/thmr_theme.dart';
import '../../../shared/widgets/thmr_panel.dart';

class VotePanel extends ConsumerStatefulWidget {
  const VotePanel({super.key, required this.status});

  final StationStatus status;

  @override
  ConsumerState<VotePanel> createState() => _VotePanelState();
}

class _VotePanelState extends ConsumerState<VotePanel> {
  String? _pendingLabel;

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(voteStatusProvider);
    final vote = result.asData?.value;
    final signedIn = ref.watch(authProvider.select((auth) => auth.signedIn));
    final round =
        vote?.matchesTrack(widget.status.station.id, widget.status.current) ==
                true
            ? vote?.round
            : null;
    final canVote = round != null && round.threshold > 0 && !round.actionTaken;
    final pendingLabel = _pendingLabel;
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final accent = theme.colorScheme.primary;
    final String detail;
    if (round?.actionTaken == true) {
      detail = '已请求切歌';
    } else if (canVote) {
      detail = '${round.votes} / ${round.threshold} 票';
    } else if (round != null && round.threshold <= 0) {
      detail = '本频道暂未开放投票';
    } else if (result.hasError) {
      final error = result.error;
      detail = error is ApiException && error.statusCode == 400
          ? '本频道暂未开放投票'
          : '投票状态读取失败';
    } else {
      detail = widget.status.current == null || vote?.active == false
          ? '等待当前曲目'
          : '正在同步投票';
    }

    return ThmrPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.how_to_vote_outlined, size: 21, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('投票切歌',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(detail,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: tokens.mutedInk)),
                if (canVote) ...[
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: LinearProgressIndicator(
                      value: (round.votes / round.threshold).clamp(0.0, 1.0),
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: tokens.panelBorder,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canVote || pendingLabel != null) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed:
                  pendingLabel == null && canVote ? () => _submit(vote!) : null,
              child: Semantics(
                liveRegion: pendingLabel != null,
                child: Text(pendingLabel ??
                    (!signedIn
                        ? '登录后投票'
                        : vote!.myVote
                            ? '撤回'
                            : '投一票')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit(VoteStatus displayed) async {
    if (_pendingLabel != null) return;
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      _notify('请在「我的」页登录后投票');
      return;
    }

    final stationId = displayed.stationId;
    final withdrawal = displayed.myVote;
    final failure = withdrawal ? '撤回失败，请稍后重试' : '投票失败，请稍后重试';
    setState(() => _pendingLabel = withdrawal ? '撤回中…' : '投票中…');
    try {
      final enabled = await ref.refresh(voteEnabledProvider.future);
      if (!mounted || !_sameSession(stationId, userId)) return;
      if (!enabled) {
        _notify('投票已暂停');
        return;
      }
      final latest = await ref.refresh(voteStatusProvider.future);
      if (!mounted || !_sameSession(stationId, userId)) return;
      if (ref.read(voteEnabledProvider).asData?.value != true) return;
      final current = ref.read(stationProvider).status?.current;
      if (!displayed.matchesTrack(stationId, current) ||
          !latest.matchesTrack(stationId, current) ||
          latest.round?.actionTaken != false ||
          (latest.round?.threshold ?? 0) <= 0) {
        _notify('投票轮次已更新，请确认后重试');
        return;
      }
      if (withdrawal != latest.myVote) {
        _notify('投票状态已更新');
        return;
      }

      final api = ref.read(authProvider.notifier).api;
      final bool skipTriggered;
      if (withdrawal) {
        await api.cancelVote(stationId);
        skipTriggered = false;
      } else {
        skipTriggered = await api.castVote(stationId);
      }
      if (!mounted || !_sameSession(stationId, userId)) return;
      if (skipTriggered) {
        _notify('票数已达阈值，已请求切换下一首');
        unawaited(ref.read(stationProvider.notifier).refresh());
      } else if (displayed.matchesTrack(
          stationId, ref.read(stationProvider).status?.current)) {
        _notify(withdrawal ? '已撤回投票' : '已投票');
      }
    } on ApiException catch (error) {
      if (!mounted || !_sameSession(stationId, userId)) return;
      _notify(error.statusCode == 401 ? '登录已过期，请在「我的」页重新登录' : failure);
    } catch (_) {
      if (mounted && _sameSession(stationId, userId)) {
        _notify(failure);
      }
    } finally {
      if (mounted) {
        setState(() => _pendingLabel = null);
        ref.invalidate(voteStatusProvider);
      }
    }
  }

  bool _sameSession(String stationId, String userId) =>
      ref.read(activeStationIdProvider) == stationId &&
      ref.read(authProvider).user?.id == userId;

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
