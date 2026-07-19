import SwiftUI

struct CodexDetailView: View {
    @ObservedObject var manager: UsageManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Official Codex Status Card
                CodexStatusCard(codex: manager.codexData)
                
                // Lifetime Summary Cards Grid
                HStack(spacing: 8) {
                    DetailCard(
                        title: "Total Tokens",
                        value: UsageManager.formatTokens(manager.codexData.totalTokens),
                        icon: "bolt.ring.closed",
                        accentGradient: MacTheme.codexGradient,
                        primaryColor: MacTheme.codexPrimary
                    )
                    
                    DetailCard(
                        title: "Sessions",
                        value: "\(manager.codexData.totalSessions)",
                        icon: "square.stack.3d.up.fill",
                        accentGradient: LinearGradient(colors: [Color.teal, Color.cyan], startPoint: .leading, endPoint: .trailing),
                        primaryColor: .teal
                    )
                    
                    DetailCard(
                        title: "Resets",
                        value: "\(manager.codexData.availableResetsCount)",
                        icon: "arrow.triangle.2.circlepath",
                        accentGradient: LinearGradient(colors: [Color.mint, Color.green], startPoint: .leading, endPoint: .trailing),
                        primaryColor: .mint
                    )
                }
                
                // Models Breakdown for Codex
                VStack(alignment: .leading, spacing: 8) {
                    Text("CODEX MODELS USED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 6) {
                        ForEach(manager.codexData.modelBreakdown) { model in
                            GlassCard(cornerRadius: 10, padding: 8) {
                                HStack {
                                    Text(model.modelName)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(model.sessionCount) sessions")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Text(UsageManager.formatTokens(model.totalTokens))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(MacTheme.codexPrimary)
                                }
                            }
                        }
                    }
                }
                
                // Daily Usage Breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("DAILY BREAKDOWN HISTORY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 6) {
                        ForEach(Array(manager.codexData.dailyUsage.prefix(10))) { item in
                            GlassCard(cornerRadius: 10, padding: 8) {
                                HStack {
                                    Text(item.date)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(item.sessionCount) session\(item.sessionCount == 1 ? "" : "s")")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    
                                    Text(UsageManager.formatTokens(item.tokensUsed))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(MacTheme.codexPrimary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}
