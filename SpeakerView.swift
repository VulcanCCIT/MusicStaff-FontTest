//
//  SpeakerView.swift
//  MusicStaff-FontTest
//
//  Created by Studio Monitor Animation
//

import SwiftUI

/// A studio monitor speaker that animates when audio is playing
///
/// Features:
/// - Wooden side panels with realistic grain texture
/// - Horn tweeter at the top (the distinctive X-shaped driver)
/// - Large woofer cone with realistic depth and shading
/// - Dual bass reflex ports at the bottom
/// - Subtle vibration animation when playing
/// - Woofer cone pulses with note velocity
struct SpeakerView: View {
    /// Whether the speaker should show active/vibrating state
    let isPlaying: Bool
    
    /// Velocity of the current note (0-127) to scale animation intensity
    let velocity: Int
    
    @State private var wooferScale: CGFloat = 1.0
    @State private var vibrationOffset: CGFloat = 0
    
    private var animationIntensity: Double {
        // Map MIDI velocity (0-127) to animation scale (0.5 - 1.0)
        Double(velocity) / 127.0 * 0.5 + 0.5
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            ZStack {
                // Wooden enclosure sides - lighter, warmer brown tones
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.35, blue: 0.15),  // Lighter warm brown
                                Color(red: 0.48, green: 0.30, blue: 0.12),  // Medium warm brown
                                Color(red: 0.42, green: 0.26, blue: 0.10)   // Darker warm brown
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 6)
                
                // Front baffle (the dark face plate) - lightened and with subtle edge lighting
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.18, blue: 0.19),  // Lighter top
                                Color(red: 0.14, green: 0.14, blue: 0.16),  // Medium
                                Color(red: 0.11, green: 0.11, blue: 0.13)   // Darker bottom
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        // Subtle inner edge highlight for depth
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.04),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .padding(width * 0.08)
                
                VStack(spacing: height * 0.06) {  // Reduced from 0.09 to allow woofer to move down
                    Spacer()
                        .frame(height: height * 0.14)  // Increased from 0.10 to push components down
                    
                    // Horn tweeter (the X-shaped compression driver at top)
                    hornTweeter
                        .frame(width: width * 0.62, height: height * 0.26)  // Increased from 0.54 and 0.22
                    
                    //Spacer()
                        .frame(height: height * 0.14)  // Maintained spacing after tweeter
                  
                  //brandLabel
                  brandLabel
                    .frame(width: width * 0.45, height: height * 0.18)
                  Spacer()
                    
                    // Woofer (main speaker cone) - balanced size
                    woofer
                        .frame(width: width * 0.49, height: width * 0.49)
                        .scaleEffect(wooferScale)
                    
                    Spacer()
                        .frame(height: height * 0.05)  // Increased to push woofer down toward bass ports
                    
                    // Bass reflex ports (two circular openings at bottom)
                    HStack(spacing: width * 0.12) {
                        bassPort
                            .frame(width: width * 0.26, height: width * 0.26)
                        
                        bassPort
                            .frame(width: width * 0.26, height: width * 0.26)
                    }
                    
                    Spacer()
                        .frame(height: height * 0.05)
                }
                .padding(.horizontal, width * 0.12)
            }
            .offset(x: vibrationOffset)
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }
    
    // MARK: - Speaker Components
    
    /// Horn tweeter - the distinctive X-shaped high-frequency driver
    private var hornTweeter: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minDim = min(w, h)
            // Use a square area to guarantee equal sides and proper rotation
            let size = minDim
            let center = CGPoint(x: w/2, y: h/2)
            let throatDiameter = size * 0.26

            ZStack {
                // Diamond (rotated square) built from uniform radius to keep equal sides
                Path { p in
                    let r = size / 2
                    p.move(to: CGPoint(x: center.x, y: center.y - r)) // top
                    p.addLine(to: CGPoint(x: center.x + r, y: center.y)) // right
                    p.addLine(to: CGPoint(x: center.x, y: center.y + r)) // bottom
                    p.addLine(to: CGPoint(x: center.x - r, y: center.y)) // left
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.40, green: 0.40, blue: 0.42),
                            Color(red: 0.25, green: 0.25, blue: 0.27),
                            Color(red: 0.15, green: 0.15, blue: 0.17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Path { p in
                        let r = size / 2
                        p.move(to: CGPoint(x: center.x, y: center.y - r))
                        p.addLine(to: CGPoint(x: center.x + r, y: center.y))
                        p.addLine(to: CGPoint(x: center.x, y: center.y + r))
                        p.addLine(to: CGPoint(x: center.x - r, y: center.y))
                        p.closeSubpath()
                    }
                    .stroke(Color.black.opacity(0.35), lineWidth: max(1, size * 0.015))
                )

                // Center throat (small circle where sound exits) kept centered
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.black,
                                Color(red: 0.1, green: 0.1, blue: 0.12)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: throatDiameter
                        )
                    )
                    .frame(width: throatDiameter, height: throatDiameter)
                    .position(center)
            }
        }
    }
    
    /// Brand label (orange accent line)
    private var brandLabel: some View {
        Rectangle()
            .fill(Color(red: 0.8, green: 0.4, blue: 0.1))
            .frame(height: 3)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 40, height: 2)
            )
    }
    
    /// Main woofer cone with realistic depth and shading
    private var woofer: some View {
        ZStack {
            // Outer mounting ring with screws
            Circle()
                .strokeBorder(Color(red: 0.2, green: 0.2, blue: 0.22), lineWidth: 2.5)
            
            // Rim lighting effect (white accent around the edge)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 75, height: 75)
            
            // Mounting screws (4 corners)
            ForEach(0..<4) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.15, green: 0.15, blue: 0.16),
                                Color(red: 0.08, green: 0.08, blue: 0.1)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 4
                        )
                    )
                    .frame(width: 5, height: 5)
                    .offset(x: cos(CGFloat(index) * .pi / 2 + .pi / 4) * 35,
                           y: sin(CGFloat(index) * .pi / 2 + .pi / 4) * 35)
            }
            
            // Surround (outer rubber suspension) with subtle highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.12, blue: 0.14),
                            Color(red: 0.08, green: 0.08, blue: 0.1),
                            Color.black
                        ],
                        center: .center,
                        startRadius: 24,
                        endRadius: 37
                    )
                )
                .overlay(
                    // Highlight arc on top edge of surround
                    Circle()
                        .trim(from: 0.6, to: 0.9)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
                        .rotationEffect(.degrees(-45))
                )
                .frame(width: 74, height: 74)
            
            // Cone (main diaphragm) with enhanced lighting
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.18, green: 0.18, blue: 0.19),  // Slightly lighter center
                            Color(red: 0.12, green: 0.12, blue: 0.14),
                            Color(red: 0.1, green: 0.1, blue: 0.12),
                            Color(red: 0.08, green: 0.08, blue: 0.1)
                        ],
                        center: UnitPoint(x: 0.4, y: 0.4),  // Light from top-left
                        startRadius: 0,
                        endRadius: 32
                    )
                )
                .overlay(
                    // Concentric rings for texture
                    ForEach(1..<4) { ring in
                        Circle()
                            .stroke(Color.black.opacity(0.2), lineWidth: 0.4)
                            .scaleEffect(CGFloat(ring) * 0.25)
                    }
                )
                .overlay(
                    // Specular highlight (light reflection)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 12
                            )
                        )
                        .frame(width: 20, height: 20)
                        .offset(x: -7, y: -7)  // Position highlight top-left
                )
                .frame(width: 56, height: 56)
            
            // Dust cap (center dome) with highlight
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.24, green: 0.24, blue: 0.26),  // Lighter for more contrast
                            Color(red: 0.15, green: 0.15, blue: 0.17),
                            Color(red: 0.1, green: 0.1, blue: 0.12)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),  // Light from top-left
                        startRadius: 0,
                        endRadius: 12
                    )
                )
                .overlay(
                    // Dust cap specular highlight
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 5
                            )
                        )
                        .frame(width: 8, height: 8)
                        .offset(x: -2.5, y: -2.5)
                )
                .frame(width: 19, height: 19)
        }
    }
    
    /// Bass reflex port (tuned port for low frequencies)
    private var bassPort: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.06, green: 0.06, blue: 0.07),  // Slightly lighter
                        Color(red: 0.10, green: 0.10, blue: 0.12)   // Lighter edge
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 20
                )
            )
            .overlay(
                Circle()
                    .strokeBorder(Color(red: 0.18, green: 0.18, blue: 0.20), lineWidth: 1)  // Lighter ring
            )
            .overlay(
                // Top-edge highlight to suggest studio lighting
                Circle()
                    .trim(from: 0.65, to: 0.85)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    .rotationEffect(.degrees(-45))
            )
    }
    
    // MARK: - Animations
    
    private func startAnimation() {
        // Woofer pumping animation - restored to original scale
        withAnimation(
            .easeInOut(duration: 0.15 * animationIntensity)
            .repeatCount(3, autoreverses: true)
        ) {
            wooferScale = 1.0 + (0.08 * animationIntensity)  // Restored to 0.08
        }
        
        // Subtle vibration
        withAnimation(
            .easeInOut(duration: 0.08)
            .repeatCount(4, autoreverses: true)
        ) {
            vibrationOffset = 0.5 * animationIntensity
        }
    }
    
    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            wooferScale = 1.0
            vibrationOffset = 0
        }
    }
}

/// Custom shape for the horn tweeter's diamond/X pattern
struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let centerX = rect.midX
        let centerY = rect.midY
        
        // Create diamond shape (rotated square)
        path.move(to: CGPoint(x: centerX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: centerY))
        path.addLine(to: CGPoint(x: centerX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: centerY))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Preview

#Preview("Idle Speaker") {
    SpeakerView(isPlaying: false, velocity: 0)
        .frame(width: 95, height: 155)
        .background(Color.gray.opacity(0.2))
}

#Preview("Playing Speaker (Soft)") {
    SpeakerView(isPlaying: true, velocity: 40)
        .frame(width: 95, height: 155)
        .background(Color.gray.opacity(0.2))
}

#Preview("Playing Speaker (Loud)") {
    SpeakerView(isPlaying: true, velocity: 127)
        .frame(width: 95, height: 155)
        .background(Color.gray.opacity(0.2))
}

#Preview("Both Speakers") {
    HStack(spacing: 40) {
        SpeakerView(isPlaying: true, velocity: 90)
            .frame(width: 95, height: 155)
        
        SpeakerView(isPlaying: true, velocity: 90)
            .frame(width: 95, height: 155)
    }
    .padding(40)
    .background(Color(red: 0.28, green: 0.07, blue: 0.08))
}

