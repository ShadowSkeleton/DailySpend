import SwiftUI

struct TestScannerView: View {
    @State private var detectedAmount: Double?
    @State private var showScanner = false
    @State private var scanErrorMessage: String?
    @State private var logs: String = "准备就绪，等待扫描..."
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("小票识别测试台")
                .font(.title)
                .bold()
            
            VStack(spacing: 10) {
                Text("识别结果")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if let amount = detectedAmount {
                    Text("$\(String(format: "%.2f", amount))")
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .foregroundColor(.green)
                } else {
                    Text("--.--")
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .foregroundColor(.gray.opacity(0.3))
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(20)
            
            Button(action: { showScanner = true }) {
                Label("启动相机扫描", systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            // 简易日志区
            ScrollView {
                Text(logs)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(height: 150)
            .background(Color.black.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .sheet(isPresented: $showScanner) {
            ReceiptScannerView(
                scannedAmount: $detectedAmount,
                scanErrorMessage: $scanErrorMessage
            )
                .ignoresSafeArea()
                .onDisappear {
                    if let amount = detectedAmount {
                        logs = "✅ 扫描完成\n识别金额: \(amount)\n(请查看 Xcode 控制台获取详细算法日志)"
                    } else if let scanErrorMessage {
                        logs = "⚠️ \(scanErrorMessage)"
                    } else {
                        logs = "⚠️ 扫描取消或未识别到金额"
                    }
                }
        }
    }
}

#Preview {
    TestScannerView()
}
