import SwiftUI

struct SettingsView: View {
    @ObservedObject private var locale = LocaleStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.t("preferences", locale: locale.current).replacingOccurrences(of: "…", with: ""))
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

            Form {
                Section {
                    Picker(L.t("language", locale: locale.current), selection: $locale.current) {
                        Text("English").tag(AppLocale.en)
                        Text("中文").tag(AppLocale.zh)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    LabeledContent("Version", value: "0.1.0")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(L.t("preferences", locale: locale.current) == "偏好设置…" ? "完成" : "Done") {
                    SettingsWindowController.shared.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 460, height: 320)
    }
}
