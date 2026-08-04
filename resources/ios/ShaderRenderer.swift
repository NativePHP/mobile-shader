import SwiftUI

/// Renderer for `<native:shader>`.
///
/// Reads the shader function name and its uniforms off the wire node, then
/// applies the matching SwiftUI effect to the element's children. Time is
/// generated here — never sent from PHP — so animation runs at display
/// refresh rate with zero bridge traffic. PHP re-renders only change the
/// *parameters*.
struct ShaderRenderer: View {
    let node: NativeUINode

    /// Fixed origin for the time uniform. Held in @State so it survives
    /// re-renders and the effect doesn't jump when props change.
    @State private var epoch = Date()

    /// SwiftUI offers no way to ask whether a shader function exists, and a
    /// missing one renders as an empty box rather than an error. The whole
    /// library is absent when the build shipped without compiled Metal — see
    /// the ensure-metal-toolchain hook — so checking once for the metallib
    /// turns that silent blank into the plain children.
    private static let hasShaderLibrary: Bool =
        Bundle.main.url(forResource: "default", withExtension: "metallib") != nil

    var body: some View {
        let props = node.props
        let function = props.getString("name")
        let mode = props.getString("mode", default: "layer")
        let animated = props.getBool("animated", default: true)
        let speed = props.getFloat("speed", default: 1)
        let uniforms = props.getStringList("uniform_names").map {
            props.getFloat("u_" + $0, default: 0)
        }

        // iOS 16, a build with no compiled Metal, and any node that forgot to
        // name a function all degrade to the plain children — an unstyled but
        // correct screen beats a blank one.
        if #available(iOS 17.0, *), !function.isEmpty, Self.hasShaderLibrary {
            GeometryReader { proxy in
                TimelineView(.animation(paused: !animated)) { timeline in
                    let elapsed = Float(timeline.date.timeIntervalSince(epoch)) * speed

                    effected(
                        function: function,
                        mode: mode,
                        size: proxy.size,
                        time: animated ? elapsed : 0,
                        uniforms: uniforms
                    )
                }
            }
        } else {
            children
        }
    }

    private var children: some View {
        ZStack {
            ForEach(node.children) { child in
                NodeView(node: child)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @available(iOS 17.0, *)
    @ViewBuilder
    private func effected(
        function: String,
        mode: String,
        size: CGSize,
        time: Float,
        uniforms: [Float]
    ) -> some View {
        let shader = makeShader(function: function, size: size, time: time, uniforms: uniforms)

        // Bounds the offscreen buffer the effect may sample outside. Too
        // small and displaced samples clip; too large and every frame pays
        // for pixels nothing reads.
        let maxSampleOffset = CGSize(width: 64, height: 64)

        switch mode {
        case "color":
            children.colorEffect(shader)
        case "distortion":
            children.distortionEffect(shader, maxSampleOffset: maxSampleOffset)
        default:
            children.layerEffect(shader, maxSampleOffset: maxSampleOffset)
        }
    }

    @available(iOS 17.0, *)
    private func makeShader(
        function: String,
        size: CGSize,
        time: Float,
        uniforms: [Float]
    ) -> Shader {
        // Positional, and deliberately so: (size, time) then the uniforms in
        // the order PHP declared them. See Elements/Shader.php.
        var arguments: [Shader.Argument] = [.float2(size), .float(time)]
        arguments.append(contentsOf: uniforms.map { .float($0) })

        // Shader(function:arguments:) rather than the variadic call syntax —
        // the uniform count is only known at runtime.
        return Shader(
            function: ShaderLibrary.default[dynamicMember: function],
            arguments: arguments
        )
    }
}
