import CoreGraphics
import Foundation

public enum PanelPlacement {
    public static func resizedFrameKeepingTopEdge(
        _ frame: CGRect,
        targetHeight: CGFloat
    ) -> CGRect {
        let height = max(targetHeight, 0)
        return CGRect(
            x: frame.minX,
            y: frame.maxY - height,
            width: frame.width,
            height: height
        )
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
