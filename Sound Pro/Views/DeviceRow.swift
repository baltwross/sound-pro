import SwiftUI

struct DeviceRow: View {
    let device: AudioDevice
    let isSelected: Bool
    @Binding var volume: Float
    let onToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: deviceIcon)
                    .font(.title3)
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            
            if isSelected {
                HStack {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1)
                        .controlSize(.small)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var deviceIcon: String {
        let lowercasedName = device.name.lowercased()
        if lowercasedName.contains("airpods") {
            if lowercasedName.contains("pro") {
                return "airpodspro"
            } else if lowercasedName.contains("max") {
                return "airpodsmax"
            }
            return "airpods"
        } else if lowercasedName.contains("headphone") {
            return "headphones"
        } else if lowercasedName.contains("speaker") || lowercasedName.contains("macbook") {
            return "hifispeaker"
        }
        return "headphones"
    }
}

