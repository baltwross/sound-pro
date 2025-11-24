import SwiftUI
import CoreAudio
import Combine

// MARK: - UI VIEW
struct ContentView: View {
    @StateObject var audioManager = AudioManager()
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "airpods.pro")
                Text("Audio Share")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)
            .padding(.horizontal)
            
            // Device List
            VStack(spacing: 0) {
                ForEach(audioManager.availableDevices, id: \.uid) { device in
                    DeviceRow(
                        device: device,
                        isSelected: audioManager.selectedDevices.contains(where: { $0.uid == device.uid }),
                        volume: Binding(
                            get: { audioManager.deviceVolumes[device.uid] ?? 0.5 },
                            set: { audioManager.setVolume($0, for: device) }
                        ),
                        onToggle: {
                            audioManager.toggleSelection(for: device)
                        }
                    )
                    
                    if device.uid != audioManager.availableDevices.last?.uid {
                        Divider()
                            .padding(.leading, 44)
                            .opacity(0.3)
                    }
                }
            }
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
            
            if audioManager.isSharing {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .symbolEffect(.pulse)
                        .foregroundStyle(.green)
                    Text("Sharing Audio to \(audioManager.selectedDevices.count) Devices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            
            // Debug button (can be removed later)
            Button("Print Debug Info") {
                audioManager.printDebugStatus()
            }
            .font(.caption2)
            .padding(.top, 4)
        }
        .padding(.vertical)
        .frame(width: 320)
        .background(.regularMaterial)
    }
}
