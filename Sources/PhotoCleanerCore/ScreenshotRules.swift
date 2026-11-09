import Foundation

public enum ScreenshotRules {
    private static let receiptWords = ["发票", "收据", "票据", "账单", "价税合计", "invoice", "receipt", "billing statement"]
    private static let documentWords = ["文档", "扫描件", "合同", "证件", "身份证", "护照", "户口", "驾驶证", "行驶证", "病历", "诊断", "银行卡", "银行账号", "银行流水", "保单", "document", "contract", "id card", "identity card", "passport", "bank account", "medical record"]

    public static func isSensitive(text: String) -> Bool {
        contains(text.lowercased(), any: receiptWords + documentWords)
    }

    public static func tags(for text: String) -> [String] {
        let normalized = text.lowercased()
        var result: [String] = []
        if contains(normalized, any: receiptWords) { result.append("票据") }
        if contains(normalized, any: documentWords) { result.append("文档") }
        // Important documents take precedence over short-lived codes and delivery text.
        guard !isSensitive(text: text) else { return result }
        if contains(normalized, any: ["验证码", "动态码", "一次性密码", "verification code", "one-time password"]) {
            result.append("验证码")
        }
        if contains(normalized, any: ["物流", "快递", "运单", "取件码", "派送", "tracking number", "shipment", "parcel"]) {
            result.append("物流")
        }
        return result
    }

    private static func contains(_ text: String, any words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }
}
