import SwiftUI
import UIKit

/// Selector visual de temas sutiles para carpetas Liquid Glass y acentos principales.
/// Incluye vista previa en vivo conservando intactos Modo Claro/Oscuro, interruptores verdes y franjas horarias.
struct ThemePickerView: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        List {
            Section {
                liveDashboardPreviewCard
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .listRowBackground(Color.clear)
            } header: {
                Text(L10n.themePickerPreviewHeader)
            }

            Section {
                ForEach(AppVisualTheme.allCases) { theme in
                    let isSelected = themeManager.currentTheme == theme
                    ThemeOptionRow(theme: theme, isSelected: isSelected) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            themeManager.currentTheme = theme
                        }
                    }
                }
            } header: {
                Text(L10n.themePickerListHeader)
            } footer: {
                Text(L10n.themePickerFooter)
            }
        }
        .navigationTitle(L10n.themePickerNavTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeManager.primaryAccent)
    }

    private var liveDashboardPreviewCard: some View {
        let colors = themeManager.currentTheme.representativeDashboardColors
        let folderItems: [(title: String, icon: String, color: Color)] = [
            (L10n.folderAll, "tray.full.fill", colors[0]),
            (L10n.folderFavorites, "star.fill", colors[1]),
            (L10n.localizedPredefinedTagName(id: "tag_ideas", fallback: "Ideas"), "lightbulb.fill", colors[2]),
            (L10n.localizedPredefinedTagName(id: "tag_microbiologia", fallback: "Microbiology"), "microbe.fill", colors[3])
        ]

        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))

            Circle()
                .fill(themeManager.primaryAccent.opacity(0.14))
                .frame(width: 170, height: 170)
                .blur(radius: 36)
                .offset(x: -70, y: -55)

            Circle()
                .fill(themeManager.secondaryGlow.opacity(0.11))
                .frame(width: 150, height: 150)
                .blur(radius: 36)
                .offset(x: 80, y: 45)

            VStack(spacing: 12) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(Array(folderItems.enumerated()), id: \.offset) { _, item in
                        MiniLiquidGlassPreviewTile(
                            title: item.title,
                            iconName: item.icon,
                            color: item.color
                        )
                    }
                }

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(themeManager.primaryAccent)
                        Text(L10n.themePickerPreviewClockSample)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(themeManager.primaryAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                    Image(systemName: DayPeriod.morning.iconName)
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: DayPeriod.morning.badgeColorHex).opacity(0.18), in: Circle())
                        .foregroundStyle(Color(hex: DayPeriod.morning.badgeColorHex))

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 10))
                        Text(L10n.boothFinishSave)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidGlassCapsule(tint: themeManager.primaryAccent, interactive: false)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: themeManager.currentTheme)
    }
}

private struct MiniLiquidGlassPreviewTile: View {
    let title: String
    let iconName: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassRoundedRect(cornerRadius: 15, tint: color.opacity(0.14), interactive: false)
    }
}

private struct ThemeOptionRow: View {
    let theme: AppVisualTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ThemeQuadThumbnail(colors: theme.representativeDashboardColors, accent: theme.primaryAccent, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.localizedTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(theme.localizedSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        ForEach(Array(theme.previewSwatches.enumerated()), id: \.offset) { _, swatch in
                            Circle()
                                .fill(swatch)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 6)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? theme.primaryAccent : Color.secondary.opacity(0.35))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeQuadThumbnail: View {
    let colors: [Color]
    let accent: Color
    let isSelected: Bool

    var body: some View {
        let safe = (0..<4).map { idx in
            idx < colors.count ? colors[idx] : accent
        }

        VStack(spacing: 3) {
            HStack(spacing: 3) {
                swatchCell(safe[0])
                swatchCell(safe[1])
            }
            HStack(spacing: 3) {
                swatchCell(safe[2])
                swatchCell(safe[3])
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.75) : Color.primary.opacity(0.10), lineWidth: isSelected ? 1.8 : 1)
        )
    }

    private func swatchCell(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color.opacity(0.24))
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            )
    }
}
