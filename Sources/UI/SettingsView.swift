import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.retentionDays) private var retentionDays: Int = 3
    @AppStorage(SettingsKey.maxItems) private var maxItems: Int = 200

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("设置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(DS.surfaceHover)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 16) {
                    // 保留时间
                    settingsRow(
                        title: "保留时间",
                        subtitle: "超过此期限的历史记录将被自动清理"
                    ) {
                        Picker("", selection: $retentionDays) {
                            ForEach(RetentionOption.allCases, id: \.self) { opt in
                                Text(opt.label).tag(opt.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }

                    Divider()
                        .padding(.horizontal, 12)

                    // 最大条目数
                    settingsRow(
                        title: "最大条目数",
                        subtitle: "超出上限时自动丢弃最旧条目"
                    ) {
                        Picker("", selection: $maxItems) {
                            ForEach(MaxItemsOption.allCases, id: \.self) { opt in
                                Text(opt.label).tag(opt.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }
                }
                .padding(16)
            }

            Divider()
                .padding(.horizontal, 16)

            // 底部按钮
            HStack {
                Spacer()
                Button("完成") {
                    onDismiss()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(DS.accent)
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DS.bg)
        .onDisappear {
            ClipboardStore.shared.applySettings()
        }
    }

    private func settingsRow<PickerContent: View>(
        title: String,
        subtitle: String,
        @ViewBuilder picker: @escaping () -> PickerContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textPrimary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(DS.textTertiary)
            picker()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}