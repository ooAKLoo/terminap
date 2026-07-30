import CoreGraphics
import Foundation

public enum PanelResizeAnchor: Equatable, Sendable {
    case topEdge
    case bottomEdge
}

public struct PanelRelativePosition: Equatable, Sendable {
    public let horizontal: CGFloat
    public let vertical: CGFloat

    public init(horizontal: CGFloat, vertical: CGFloat) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

public enum PanelPlacement {
    public static func resizedFrame(
        _ frame: CGRect,
        targetHeight: CGFloat,
        keeping anchor: PanelResizeAnchor
    ) -> CGRect {
        let height = max(targetHeight, 0)
        let originY: CGFloat
        switch anchor {
        case .topEdge:
            originY = frame.maxY - height
        case .bottomEdge:
            originY = frame.minY
        }
        return CGRect(
            x: frame.minX,
            y: originY,
            width: frame.width,
            height: height
        )
    }

    public static func resizedFrameKeepingTopEdge(
        _ frame: CGRect,
        targetHeight: CGFloat
    ) -> CGRect {
        resizedFrame(
            frame,
            targetHeight: targetHeight,
            keeping: .topEdge
        )
    }

    public static func preferredResizeAnchor(
        for frame: CGRect,
        targetHeight: CGFloat,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> PanelResizeAnchor {
        let topAnchoredFrame = resizedFrame(
            frame,
            targetHeight: targetHeight,
            keeping: .topEdge
        )
        return topAnchoredFrame.minY < visibleFrame.minY + margin
            ? .bottomEdge
            : .topEdge
    }

    public static func topTrailingOrigin(
        panelSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGPoint {
        clampedOrigin(
            CGPoint(
                x: visibleFrame.maxX - panelSize.width - margin,
                y: visibleFrame.maxY - panelSize.height - margin
            ),
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            margin: margin
        )
    }

    public static func relativePosition(
        for origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> PanelRelativePosition {
        let bounds = originBounds(
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            margin: margin
        )
        let clampedOrigin = clampedOrigin(
            origin,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            margin: margin
        )
        return PanelRelativePosition(
            horizontal: normalizedValue(
                clampedOrigin.x,
                lowerBound: bounds.minX,
                upperBound: bounds.maxX
            ),
            vertical: normalizedValue(
                clampedOrigin.y,
                lowerBound: bounds.minY,
                upperBound: bounds.maxY
            )
        )
    }

    public static func origin(
        for relativePosition: PanelRelativePosition,
        panelSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGPoint {
        let bounds = originBounds(
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            margin: margin
        )
        return CGPoint(
            x: interpolatedValue(
                relativePosition.horizontal,
                lowerBound: bounds.minX,
                upperBound: bounds.maxX
            ),
            y: interpolatedValue(
                relativePosition.vertical,
                lowerBound: bounds.minY,
                upperBound: bounds.maxY
            )
        )
    }

    public static func clampedOrigin(
        _ origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: clampAxis(
                origin.x,
                itemLength: panelSize.width,
                lowerBound: visibleFrame.minX,
                upperBound: visibleFrame.maxX,
                margin: margin
            ),
            y: clampAxis(
                origin.y,
                itemLength: panelSize.height,
                lowerBound: visibleFrame.minY,
                upperBound: visibleFrame.maxY,
                margin: margin
            )
        )
    }

    private static func originBounds(
        panelSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGRect {
        let horizontal = originLimits(
            itemLength: panelSize.width,
            lowerBound: visibleFrame.minX,
            upperBound: visibleFrame.maxX,
            margin: margin
        )
        let vertical = originLimits(
            itemLength: panelSize.height,
            lowerBound: visibleFrame.minY,
            upperBound: visibleFrame.maxY,
            margin: margin
        )
        return CGRect(
            x: horizontal.lower,
            y: vertical.lower,
            width: horizontal.upper - horizontal.lower,
            height: vertical.upper - vertical.lower
        )
    }

    private static func originLimits(
        itemLength: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat,
        margin: CGFloat
    ) -> (lower: CGFloat, upper: CGFloat) {
        let safeLower = lowerBound + margin
        let safeUpper = upperBound - margin - itemLength
        guard safeUpper >= safeLower else {
            let centered =
                lowerBound
                + max((upperBound - lowerBound - itemLength) / 2, 0)
            return (centered, centered)
        }
        return (safeLower, safeUpper)
    }

    private static func normalizedValue(
        _ value: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        guard upperBound > lowerBound else {
            return 0.5
        }
        return min(max((value - lowerBound) / (upperBound - lowerBound), 0), 1)
    }

    private static func interpolatedValue(
        _ fraction: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        guard upperBound > lowerBound else {
            return lowerBound
        }
        let clampedFraction = min(max(fraction, 0), 1)
        return lowerBound + ((upperBound - lowerBound) * clampedFraction)
    }

    private static func clampAxis(
        _ value: CGFloat,
        itemLength: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat,
        margin: CGFloat
    ) -> CGFloat {
        let safeLower = lowerBound + margin
        let safeUpper = upperBound - margin - itemLength
        guard safeUpper >= safeLower else {
            return lowerBound + max((upperBound - lowerBound - itemLength) / 2, 0)
        }
        return min(max(value, safeLower), safeUpper)
    }
}
