import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_profile.dart';
import '../../models/call_session.dart';
import '../../models/call_log.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/liquid_glass_card.dart';

enum CallFilter { all, incoming, outgoing, missed }

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  CallFilter _selectedFilter = CallFilter.all;

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final allLogs = appState.callHistory;

    final filteredLogs = allLogs.where((log) {
      if (_selectedFilter == CallFilter.all) return true;
      if (_selectedFilter == CallFilter.incoming) return log.direction == CallDirection.incoming;
      if (_selectedFilter == CallFilter.outgoing) return log.direction == CallDirection.outgoing;
      if (_selectedFilter == CallFilter.missed) return log.direction == CallDirection.missed;
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Arama Geçmişi',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Karta basarak aramayı anında tekrarlayın',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Liquid Glass Filter Chips (Tümü, Gelen, Giden, Cevapsız)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(CallFilter.all, 'Tümü', Icons.call_rounded),
                const SizedBox(width: 8),
                _buildFilterChip(CallFilter.incoming, 'Gelen', Icons.call_received_rounded),
                const SizedBox(width: 8),
                _buildFilterChip(CallFilter.outgoing, 'Giden', Icons.call_made_rounded),
                const SizedBox(width: 8),
                _buildFilterChip(CallFilter.missed, 'Cevapsız', Icons.call_missed_rounded),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (filteredLogs.isEmpty)
            LiquidGlassCard(
              child: Column(
                children: [
                  const Icon(Icons.call_end_rounded, color: Colors.white70, size: 40),
                  const SizedBox(height: 10),
                  Text(
                    allLogs.isEmpty
                        ? 'Henüz Arama Geçmişi Yok'
                        : 'Bu Filtrede Arama Bulunmuyor',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Kişiler sekmesinden tek tıkla sesli ve görüntülü arama başlatabilirsiniz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            )
          else ...[
            for (final log in filteredLogs) ...[
              Builder(builder: (context) {
                return LiquidGlassCard(
                  onTap: () => _redial(appState, log),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: _getDirectionColor(log.direction).withValues(alpha: 0.25),
                        child: Icon(
                          _getDirectionIcon(log.direction),
                          color: _getDirectionColor(log.direction),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  log.deviceName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  log.callType == CallType.video
                                      ? Icons.videocam_rounded
                                      : Icons.call_rounded,
                                  color: Colors.white70,
                                  size: 14,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_getDirectionTitle(log.direction)} • ${log.formattedTime} (${log.formattedDuration})',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _redial(appState, log),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.replay_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Tekrar Ara',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  void _redial(AppStateProvider appState, CallLog log) {
    final targetDevice = appState.pairedDevicesList.firstWhere(
      (d) => d.id == log.deviceId || d.pairCode == log.deviceId.split('_').last,
      orElse: () => UserProfile(
        id: log.deviceId,
        deviceName: log.deviceName,
        role: log.role,
        pairCode: log.deviceId.split('_').last,
        lastSeen: DateTime.now(),
      ),
    );

    appState.selectActiveDevice(targetDevice);
    appState.startCall(log.callType);
  }

  Widget _buildFilterChip(CallFilter filter, String label, IconData icon) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getDirectionIcon(CallDirection direction) {
    switch (direction) {
      case CallDirection.incoming:
        return Icons.call_received_rounded;
      case CallDirection.outgoing:
        return Icons.call_made_rounded;
      case CallDirection.missed:
        return Icons.call_missed_rounded;
    }
  }

  Color _getDirectionColor(CallDirection direction) {
    switch (direction) {
      case CallDirection.incoming:
        return const Color(0xFF22C55E);
      case CallDirection.outgoing:
        return const Color(0xFF38BDF8);
      case CallDirection.missed:
        return const Color(0xFFEF4444);
    }
  }

  String _getDirectionTitle(CallDirection direction) {
    switch (direction) {
      case CallDirection.incoming:
        return 'Gelen Arama';
      case CallDirection.outgoing:
        return 'Giden Arama';
      case CallDirection.missed:
        return 'Cevapsız Arama';
    }
  }
}
