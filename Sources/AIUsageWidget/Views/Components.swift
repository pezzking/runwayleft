import SwiftUI

struct DetailCard: View {
    let title: String
    let value: String
    let icon: String
    let accentGradient: LinearGradient
    let primaryColor: Color
    
    var body: some View {
        GlassCard(cornerRadius: 12, padding: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentGradient.opacity(0.18))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(primaryColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                
                Spacer(minLength: 0)
            }
        }
    }
}

struct ClaudeModelRow: View {
    let model: ClaudeModelDetail
    
    var body: some View {
        GlassCard(cornerRadius: 10, padding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.modelName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(UsageManager.formatTokens(model.totalTokens))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(MacTheme.claudePrimary)
                }
                
                HStack(spacing: 6) {
                    LabelBadge(label: "In", val: UsageManager.formatTokens(model.inputTokens))
                    LabelBadge(label: "Out", val: UsageManager.formatTokens(model.outputTokens))
                    LabelBadge(label: "Cache Read", val: UsageManager.formatTokens(model.cacheReadInputTokens))
                }
            }
        }
    }
}

struct LabelBadge: View {
    let label: String
    let val: String
    
    var body: some View {
        HStack(spacing: 3) {
            Text("\(label):")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(val)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

struct SourceRow: View {
    let name: String
    let path: String
    let exists: Bool
    
    var body: some View {
        GlassCard(cornerRadius: 10, padding: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                    Text(path)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: exists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(exists ? "Connected" : "Missing")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                }
                .foregroundColor(exists ? MacTheme.success : MacTheme.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill((exists ? MacTheme.success : MacTheme.warning).opacity(0.15))
                )
            }
        }
    }
}
