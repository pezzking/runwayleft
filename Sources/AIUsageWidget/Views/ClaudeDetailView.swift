import SwiftUI

struct ClaudeDetailView: View {
    @ObservedObject var manager: UsageManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Official Claude Subscription Status Card
                ClaudeStatusCard(claude: manager.claudeData)
                
                // Header Stats Grid
                HStack(spacing: 10) {
                    DetailCard(
                        title: "Total Messages",
                        value: "\(manager.claudeData.totalMessages)",
                        icon: "bubble.left.and.bubble.right.fill",
                        accentGradient: MacTheme.claudeGradient,
                        primaryColor: MacTheme.claudePrimary
                    )
                    
                    DetailCard(
                        title: "Total Sessions",
                        value: "\(manager.claudeData.totalSessions)",
                        icon: "square.stack.3d.up.fill",
                        accentGradient: LinearGradient(colors: [Color.purple, Color.pink], startPoint: .leading, endPoint: .trailing),
                        primaryColor: .pink
                    )
                }
                
                // Model Tokens Breakdown Table
                VStack(alignment: .leading, spacing: 8) {
                    Text("CLAUDE MODELS OVERVIEW")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 6) {
                        ForEach(manager.claudeData.modelUsage) { model in
                            ClaudeModelRow(model: model)
                        }
                    }
                }
                
                // Daily Activity Log
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT DAILY ACTIVITY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 6) {
                        ForEach(Array(manager.claudeData.dailyActivity.suffix(10).reversed())) { act in
                            GlassCard(cornerRadius: 10, padding: 8) {
                                HStack {
                                    Text(act.date)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    
                                    HStack(spacing: 4) {
                                        Text("\(act.messageCount)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(MacTheme.claudePrimary)
                                        Text("msgs")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text("•")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 4) {
                                        Text("\(act.toolCallCount)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text("tools")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
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
