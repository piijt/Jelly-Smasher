import AppKit
import Carbon

let isTrial = CommandLine.arguments.dropFirst().contains { $0.hasPrefix("--") && $0 != "--no-shake" && $0 != "--dev" }
// Dev mode: endless gold, a level picker in the shop, and `--dev N` starts at level N. Its scores never count as a best.
let isDev = CommandLine.arguments.contains("--dev")
let devGold = 999_999
let screenArea = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
// Trials keep a fixed stage so their numbers stay comparable; the game fills most of the screen.
let windowSize = isTrial ? NSSize(width: 900, height: 560) : NSSize(width: screenArea.width - 20, height: screenArea.height - 20)
let gravity: CGFloat = 1500
let sliceSpeed: CGFloat = 480
// Spin in radians per second above which the axe turns into a whirlwind.
let whirlSpin: CGFloat = 8
let penguinReach: CGFloat = 58
// Past this many slimes each one is drawn with a coarser outline and without its inner bubbles.
let crowdedAt = 8

struct Burst {
    let point: CGPoint
    let born: CGFloat
    let size: CGFloat
    let isRing: Bool
    var color = NSColor.systemYellow
}

let saberGlows = [NSColor(calibratedRed: 1, green: 0.16, blue: 0.14, alpha: 1),
                  NSColor(calibratedRed: 0.2, green: 0.5, blue: 1, alpha: 1),
                  NSColor(calibratedRed: 0.72, green: 0.25, blue: 1, alpha: 1)]

enum Weapon {
    case bat, katana, saber, fish, axe

    var length: CGFloat { [150, 175, 170, 140, 165][index] }

    // Where the weight sits along the weapon: a barrel-heavy bat swings slower than a light blade.
    var balance: CGFloat { [0.65, 0.45, 0.3, 0.6, 0.85][index] }

    var damping: CGFloat { [1.4, 1.0, 0.9, 1.2, 0.35][index] }

    var isBlade: Bool { self == .katana || self == .saber }

    var isBlunt: Bool { self == .bat || self == .fish || self == .axe }

    var isSmash: Bool { self == .bat || self == .fish }

    // How much of the swing's speed a smash hands to the jelly.
    var knock: CGFloat { self == .fish ? 0.85 : 1 }

    var index: Int { Weapon.all.firstIndex(of: self) ?? 0 }

    var label: String { ["⚾ bat", "⚔️ katana", "✨ saber", "🐟 fish", "🪓 axe"][index] }

    var hit: String { self == .fish ? "SLAP" : self == .axe ? "CHOP" : "BOINK" }

    var price: Int { [0, 40, 90, 25, 60][index] }

    var tierNames: [String] {
        [["Wooden bat", "Aluminium bat", "Nail bat"],
         ["Katana", "Tamahagane katana", "Muramasa"],
         ["Red saber", "Blue saber", "Purple saber"],
         ["Herring", "Salmon", "Swordfish"],
         ["Hatchet", "Battle axe", "Golden axe"]][index]
    }

    var icon: String { String(label.prefix { $0 != " " }) }

    // Each forge step costs more than the last.
    func forgePrice(toTier tier: Int) -> Int { Int(CGFloat(max(25, price)) * (tier == 1 ? 0.9 : 2.2)) }

    var blurb: String { ["", "fast clean slices", "slices that sear", "a light, slappy smash", "heavy chops and a whirlwind"][index] }

    static let all: [Weapon] = [.bat, .katana, .saber, .fish, .axe]
}

enum Upgrade: Int, CaseIterable {
    case power, time, heft, greed

    var label: String { ["💪 Power · +15% damage", "⏱ Time · +2 s per level", "🏏 Heft · bat and fish knock 20% harder", "🪙 Greed · +25% gold"][rawValue] }

    var basePrice: Int { [20, 15, 15, 25][rawValue] }
}

let maxRank = 5
let forgeBoost: CGFloat = 0.1

enum Ware {
    case weapon(Weapon), forge(Weapon), upgrade(Upgrade)
}

struct Cut {
    let point: CGPoint
    let direction: CGVector

    var normal: CGVector { CGVector(dx: -direction.dy, dy: direction.dx) }
}
let barrelRadius: CGFloat = 10
let tick: CGFloat = 1.0 / 60
let substeps = 8
let swooshLength = 22
let groundHeight: CGFloat = 150

let blobRadius: CGFloat = 64
let blobTop: CGFloat = 54
let blobBottom: CGFloat = 22
let blobPoints = 56
let blobStiffness: CGFloat = 260
let blobSmoothing: CGFloat = 900
let blobDamping: CGFloat = 7
let popKick: CGFloat = 380

let fleeRange: CGFloat = 260
let fleeSpeed: CGFloat = 190
let dashSpeed: CGFloat = 420
let dashFor: CGFloat = 0.6
let corneredBeforeDash: CGFloat = 1.0
let boinkSpeed: CGFloat = 450
let airGravity: CGFloat = 1700
let bounceKeep: CGFloat = 0.78
let bounceFrom: CGFloat = 180
let wallBounce: CGFloat = 0.85
let maxLaunch: CGFloat = 1000
let dodgeMargin: CGFloat = 45
let dizzyFor: CGFloat = 1.2
let dizzyPerPower: CGFloat = 0.9
let soreFor: CGFloat = 1.5
let comboWindow: CGFloat = 2
let koFor: CGFloat = 0.8
let levelFor: CGFloat = 10
let countFrom = 5
let minSplitSize: CGFloat = 0.85
let splitShrink: CGFloat = 0.7
let healDelay: CGFloat = 2.5
let healPerSecond: CGFloat = 8
let windupFor: CGFloat = 0.7
let maxStartSlimes = 5
let maxSlimes = 14
let shockReach: CGFloat = 180
let shockShare: CGFloat = 0.5
let maxKnock: CGFloat = 1400
let tumbleFriction: CGFloat = 0.975
let splatSpeed: CGFloat = 450
let bowlSpeed: CGFloat = 300
let chopPower: CGFloat = 1.35
let stunFor: CGFloat = 2
let slimeFor: CGFloat = 3.5
let leapTime: CGFloat = 0.55
let leapGravity: CGFloat = 1800
let leapReach: CGFloat = 330
let spitSpeed: CGFloat = 620
let spitGravity: CGFloat = 500

enum Fury { case idle, windup, leap, spit, stunned }

struct Slime {
    var position: CGPoint
    var velocity: CGVector
}

let comboWords = ["", "BOINK!", "DOUBLE BOINK!", "TRIPLE BOINK!!", "QUADRA BOINK!!!", "BOINKTACULAR!!!!"]

struct Particle {
    var position: CGPoint
    var velocity: CGVector
    var life: CGFloat
    let span: CGFloat
    let size: CGFloat
    let color: NSColor
}

struct Popup {
    let text: String
    let position: CGPoint
    let born: CGFloat
    let color: NSColor
    let size: CGFloat
}

enum Weird: CaseIterable { case spin, rainbow, googly }

enum Grip { case handle, barrel }

func angleFromDown(_ dx: CGFloat, _ dy: CGFloat) -> CGFloat { atan2(dx, -dy) }

func nearest(_ angle: CGFloat, to reference: CGFloat) -> CGFloat {
    angle + (2 * .pi) * ((reference - angle) / (2 * .pi)).rounded()
}

func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { max(low, min(high, value)) }

struct Jelly {
    var center: CGPoint
    var radii: [CGFloat]
    var speeds: [CGFloat]
    var peak: CGFloat

    // Each point moves only along its own spoke from the center, so the outline can never fold over itself.
    static let spokes: [CGVector] = (0..<blobPoints).map { index in
        let rest = shape(index, time: 0)
        let length = hypot(rest.dx, rest.dy)
        return CGVector(dx: rest.dx / length, dy: rest.dy / length)
    }

    init(center: CGPoint) {
        self.center = center
        radii = (0..<blobPoints).map { Jelly.restRadius($0, time: 0) }
        speeds = Array(repeating: 0, count: blobPoints)
        peak = center.y + blobTop
    }

    // A gumdrop: a tall rounded top, a squashed base, and a slow breathing ripple.
    static func shape(_ index: Int, time: CGFloat) -> CGVector {
        let angle = CGFloat(index) / CGFloat(blobPoints) * 2 * .pi
        let breath = 1 + 0.035 * sin(3 * angle + time * 2.2) + 0.02 * sin(time * 1.3)
        let height = sin(angle) > 0 ? blobTop : blobBottom
        let squareness: CGFloat = sin(angle) > 0 ? 0.85 : 0.45
        let x = copysign(pow(abs(cos(angle)), squareness), cos(angle))
        return CGVector(dx: x * blobRadius * breath, dy: sin(angle) * height * breath)
    }

    static func restRadius(_ index: Int, time: CGFloat) -> CGFloat {
        let rest = shape(index, time: time)
        return hypot(rest.dx, rest.dy)
    }

    static func restRadii(time: CGFloat) -> [CGFloat] { (0..<blobPoints).map { restRadius($0, time: time) } }

    var points: [CGPoint] {
        zip(Jelly.spokes, radii).map { CGPoint(x: center.x + $0.dx * $1, y: center.y + $0.dy * $1) }
    }

    // Every slime breathes in step, so the rest shape is worked out once per frame and shared.
    mutating func step(center: CGPoint, floor: CGFloat, rest: [CGFloat], dt: CGFloat) {
        self.center = center
        let previous = radii

        for i in 0..<blobPoints {
            let left = previous[(i + blobPoints - 1) % blobPoints]
            let right = previous[(i + 1) % blobPoints]
            let force = blobStiffness * (rest[i] - previous[i]) + blobSmoothing * ((left + right) / 2 - previous[i]) - blobDamping * speeds[i]
            speeds[i] += force * dt
        }

        peak = -.infinity
        for i in 0..<blobPoints {
            radii[i] += speeds[i] * dt
            let spoke = Jelly.spokes[i]
            if radii[i] < rest[i] * 0.35 { radii[i] = rest[i] * 0.35; speeds[i] = abs(speeds[i]) * 0.3 }
            if spoke.dy < 0 {
                let toFloor = (center.y - floor) / -spoke.dy
                if radii[i] > toFloor { radii[i] = toFloor; speeds[i] = -abs(speeds[i]) * 0.3 }
            }
            peak = max(peak, center.y + spoke.dy * radii[i])
        }
    }

    mutating func wobble(toward direction: CGVector, strength: CGFloat = 1) {
        let length = max(hypot(direction.dx, direction.dy), 0.001)
        for i in 0..<blobPoints {
            let spoke = Jelly.spokes[i]
            let facing = (spoke.dx * direction.dx + spoke.dy * direction.dy) / length
            speeds[i] += popKick * strength * (facing > 0 ? -facing : 0.25)
        }
    }

    // A blunt hit caves in the side it lands on and bulges the rest out.
    mutating func dent(toward direction: CGVector, strength: CGFloat) {
        let length = max(hypot(direction.dx, direction.dy), 0.001)
        for i in 0..<blobPoints {
            let spoke = Jelly.spokes[i]
            let facing = (spoke.dx * direction.dx + spoke.dy * direction.dy) / length
            speeds[i] += popKick * strength * (facing > 0 ? -1.6 * pow(facing, 4) : 0.3 * -facing)
        }
    }

    // Speeding up leaves the jelly behind: the leading side squashes and the trailing side bulges.
    mutating func slosh(acceleration: CGFloat) {
        for i in 0..<blobPoints {
            speeds[i] -= Jelly.spokes[i].dx * acceleration * 0.012
        }
    }

    var path: NSBezierPath { path(every: 1) }

    func path(every step: Int) -> NSBezierPath {
        let all = points
        let points = Swift.stride(from: 0, to: blobPoints, by: step).map { all[$0] }
        let path = NSBezierPath()
        let count = points.count
        path.move(to: points[0])
        for i in 0..<count {
            let p0 = points[(i + count - 1) % count]
            let p1 = points[i]
            let p2 = points[(i + 1) % count]
            let p3 = points[(i + 2) % count]
            path.curve(
                to: p2,
                controlPoint1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                controlPoint2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.close()
        return path
    }
}

struct Blob {
    var size: CGFloat = 1
    var jellyX: CGFloat = windowSize.width * 0.78
    var jellySpeed: CGFloat = 0
    var corneredFor: CGFloat = 0
    var dashUntil: CGFloat = -1000
    var dashDirection: CGFloat = 0
    var isScared = false
    var scaredAt: CGFloat = -1000
    var boinkedAt: CGFloat = -1000
    var shakenAt: CGFloat = -1000
    var tumbling = false
    var dodgedAt: CGFloat = -1000
    var isNearMiss = false
    var boinkPower: CGFloat = 0
    var impact: CGFloat = 0
    var airHits = 0
    var weird: Set<Weird> = []
    var jelly: Jelly
    var health: CGFloat
    let maxHealth: CGFloat
    var koAt: CGFloat = -1000
    var rage: CGFloat = 0
    var fury = Fury.idle
    var furyAt: CGFloat = -1000
    var lift: CGFloat = 0
    var liftSpeed: CGFloat = 0
    var leapSpeed: CGFloat = 0
    var didLeapHit = false
    var slime: Slime?

    init(size: CGFloat = 1, health: CGFloat = levelHealth(1), at x: CGFloat = windowSize.width * 0.78) {
        self.size = size
        self.health = health
        maxHealth = health
        jellyX = x
        jelly = Jelly(center: CGPoint(x: x, y: groundHeight + blobBottom + 2))
    }

    var isAirborne: Bool { fury != .leap && (lift > 0 || liftSpeed > 0) }

    var isEnraged: Bool { fury == .windup || fury == .leap || fury == .spit }

    var isGone: Bool { koAt > -1000 }
}

// Size and count stop growing because every slime on screen costs drawing time; past that, levels make them tougher instead.
func levelSize(_ level: Int) -> CGFloat { min(1.4, 0.95 + 0.05 * CGFloat(level)) }

func levelHealth(_ level: Int) -> CGFloat { 60 + 15 * CGFloat(level - 1) + 40 * CGFloat(max(0, level - maxStartSlimes)) }

func levelSlimes(_ level: Int) -> Int { min(level, maxStartSlimes) }

final class BoinkView: NSView {
    var handleAt = CGPoint(x: windowSize.width / 2 - 150, y: groundHeight + penguinReach)
    var angle: CGFloat = 0.9
    var spin: CGFloat = 0
    var handleVelocity = CGVector.zero
    var held: Grip?
    var heldAt = CGPoint.zero
    var grabOffset = CGVector.zero
    var swoosh: [CGPoint] = []
    var lastBarrel = CGPoint.zero
    var clock: CGFloat = 0

    var blobs = [Blob()]
    var current = 0

    var me: Blob {
        get { blobs[current] }
        _modify { yield &blobs[current] }
    }
    var boinks = 0
    var dodges = 0
    var score = 0
    var best = isTrial ? 0 : UserDefaults.standard.integer(forKey: "bestScore")
    var combo = 0
    var bestCombo = 0
    var kos = 0
    var bannerText = ""
    var bannerColor = NSColor.systemOrange
    var bannerAt: CGFloat = -1000
    var particles: [Particle] = []
    var popups: [Popup] = []
    var shake: CGFloat = 0
    var hitstop = 0
    var slimedAt: CGFloat = -1000
    var slimeGrip = CGPoint.zero
    var jellyHits = 0
    var weapon = Weapon.bat
    var gold = isDev ? devGold : 0
    var nextLevel = 2
    var owned: Set<Weapon> = [.bat]
    var ranks: [Upgrade: Int] = [:]
    var tiers: [Weapon: Int] = [:]
    var isShopping = false
    var countdownAt: CGFloat = -1000
    var upcoming = 1
    var shownCount = 0
    var slices = 0
    var cut: Cut?
    var slicedAt: CGFloat = -1000
    var level = 1
    var levelAt: CGFloat = 0
    var clearedAt: CGFloat = -1000
    var gameOverAt: CGFloat = -1000
    var lastHitWasSlice = false
    var penguinHurtAt: CGFloat = -1000
    var penguinCheerAt: CGFloat = -1000
    var bursts: [Burst] = []
    var lastHitAt: CGFloat = -1000
    var cutWeapon = Weapon.katana
    var hitWeapon = Weapon.bat

    var ground: CGFloat { groundHeight }

    var jellyCenter: CGPoint { CGPoint(x: me.jellyX, y: ground + me.lift + blobBottom + 2) }

    var bodyCenter: CGPoint { CGPoint(x: me.jellyX, y: ground + me.lift + (blobBottom + 2) * me.size) }

    var jellyTop: CGFloat { ground + me.lift + (blobBottom + 2 + blobTop) * me.size }

    var radius: CGFloat { blobRadius * me.size }

    var head: CGPoint { CGPoint(x: me.jellyX, y: ground + me.lift + (blobBottom + 2 + blobTop * 0.65) * me.size) }

    var handle: CGPoint { handleAt }

    var barrel: CGPoint { CGPoint(x: handleAt.x + weapon.length * sin(angle), y: handleAt.y - weapon.length * cos(angle)) }

    func age(_ moment: CGFloat) -> CGFloat { clock - moment }

    var sinceBoink: CGFloat { age(me.boinkedAt) }

    var dizzyTime: CGFloat { CGFloat(dizzyFor + dizzyPerPower * Double(me.boinkPower)) }

    var isDizzy: Bool { sinceBoink < dizzyTime || age(me.shakenAt) < dizzyFor }

    var sinceKO: CGFloat { CGFloat(age(me.koAt)) }

    var isKO: Bool { sinceKO < CGFloat(koFor) }

    var isComboLive: Bool { combo > 0 && (age(lastHitAt) < comboWindow || isAnyAirborne) }

    var isAnyAirborne: Bool { blobs.contains { $0.isAirborne } }

    var isAnyEnraged: Bool { blobs.contains { $0.isEnraged } }

    var levelTime: CGFloat { levelFor + 2 * CGFloat(rank(.time)) }

    var timeLeft: CGFloat { max(0, levelTime - age(levelAt)) }

    func rank(_ upgrade: Upgrade) -> Int { ranks[upgrade, default: 0] }

    func tier(_ choice: Weapon) -> Int { tiers[choice, default: 0] }

    var isGameOver: Bool { gameOverAt > -1000 }

    var canRestart: Bool { isGameOver && age(gameOverAt) > 0.8 }

    var isVibing = false

    var blowsBubbles = isTrial || UserDefaults.standard.object(forKey: "vibeBubbles") as? Bool ?? true

    var shakesScreen = !CommandLine.arguments.contains("--no-shake") && (isTrial || UserDefaults.standard.object(forKey: "screenShake") as? Bool ?? true)

    var vibeClock: CGFloat = 0

    var isAirborne: Bool { me.isAirborne }

    var ceilingLift: CGFloat { bounds.maxY - ground - (blobBottom + 2 + blobTop) * me.size }

    // Damage and points follow the swing's kinetic energy, so a slow poke barely tickles.
    var hitPoints: Int { Int(min(600, 40 * me.impact * me.impact)) }

    var isEnraged: Bool { me.isEnraged }

    var shownRage: CGFloat { isEnraged ? 1 : min(1, me.rage) }

    var isStunned: Bool { me.fury == .stunned }

    var isSlimed: Bool { age(slimedAt) < slimeFor }

    var isSore: Bool { !isDizzy && sinceBoink < dizzyTime + CGFloat(soreFor) }

    var isRelieved: Bool { age(me.dodgedAt) < 0.9 && !isDizzy }

    var isDashing: Bool { clock < me.dashUntil }

    var isCornered: Bool { me.corneredFor > 0.15 && !isDashing }

    func isWeird(_ effect: Weird) -> Bool { isDizzy && me.weird.contains(effect) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func isNear(_ a: CGPoint, _ b: CGPoint, _ radius: CGFloat) -> Bool { hypot(a.x - b.x, a.y - b.y) <= radius }

    var penguinCenter: CGPoint { CGPoint(x: handleAt.x, y: handleAt.y - 30) }

    var penguinFacing: CGFloat {
        let nearest = blobs.min { abs($0.jellyX - handleAt.x) < abs($1.jellyX - handleAt.x) }
        return (nearest?.jellyX ?? bounds.maxX) >= handleAt.x ? 1 : -1
    }

    var isPenguinAirborne: Bool { handleAt.y - penguinReach > ground + 3 }

    func grip(at point: CGPoint) -> Grip? {
        if isNear(point, barrel, barrelRadius + 14) { return .barrel }
        if isNear(point, handle, 16) { return .handle }
        let body = CGVector(dx: (point.x - penguinCenter.x) / 20, dy: (point.y - penguinCenter.y) / 26)
        if body.dx * body.dx + body.dy * body.dy < 1 { return .handle }
        let dx = barrel.x - handle.x
        let dy = barrel.y - handle.y
        let t = ((point.x - handle.x) * dx + (point.y - handle.y) * dy) / (weapon.length * weapon.length)
        guard (0...1).contains(t), meanSegmentDistance(from: point) < 12 else { return nil }
        return t < 0.45 ? .handle : .barrel
    }

    func grab(_ grip: Grip, at point: CGPoint) {
        held = grip
        heldAt = point
        slimeGrip = point
        grabOffset = grip == .handle ? CGVector(dx: handleAt.x - point.x, dy: handleAt.y - point.y) : .zero
    }

    var toggleFrame: NSRect { NSRect(x: 16, y: bounds.maxY - 116, width: 430, height: 26) }

    var vibeFrame: NSRect { NSRect(x: toggleFrame.maxX + 8, y: toggleFrame.minY, width: 84, height: toggleFrame.height) }

    func isOverToggle(_ point: CGPoint) -> Bool { toggleFrame.contains(point) || vibeFrame.contains(point) }

    var isWhirling: Bool { weapon == .axe && abs(spin) > whirlSpin && !isGameOver }

    var whirlReach: CGFloat { weapon.length + 20 }

    var vibeSeat: CGPoint { CGPoint(x: bounds.maxX - 70, y: bounds.minY + 30) }

    func isOverVibingPenguin(_ point: CGPoint) -> Bool { isNear(point, CGPoint(x: vibeSeat.x, y: vibeSeat.y + 22), 36) }

    @objc func pickVibe(_ item: NSMenuItem) {
        blowsBubbles = item.tag == 1
        UserDefaults.standard.set(blowsBubbles, forKey: "vibeBubbles")
        needsDisplay = true
    }

    @objc func toggleShake() {
        shakesScreen.toggle()
        UserDefaults.standard.set(shakesScreen, forKey: "screenShake")
    }

    @objc func toggleVibe() {
        guard !isGameOver else { return }
        isVibing.toggle()
        held = nil
        needsDisplay = true
    }

    @objc func pickWeapon(_ item: NSMenuItem) { arm(Weapon.all[item.tag]) }

    func arm(_ next: Weapon) {
        guard next != weapon else { return }
        weapon = next
        swoosh = []
        NSSound(named: ["Tink", "Glass", "Submarine", "Morse", "Sosumi"][next.index])?.play()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isVibing {
            if isOverVibingPenguin(point) { toggleVibe() }
            return
        }
        if canRestart {
            reset()
            return
        }
        if vibeFrame.contains(point) {
            toggleVibe()
            return
        }
        if isShopping && shopFrame.contains(point) {
            if nextFrame.contains(point) {
                leaveShop()
            } else if let pick = devSteps.first(where: { $0.frame.contains(point) }) {
                nextLevel = max(1, nextLevel + pick.step)
                NSSound(named: "Tink")?.play()
            } else if let row = wares.indices.first(where: { wareFrame($0).contains(point) }) {
                buy(wares[row])
            }
            return
        }
        if isOverToggle(point) {
            let choice = Weapon.all[min(Weapon.all.count - 1, Int((point.x - toggleFrame.minX) / (toggleFrame.width / CGFloat(Weapon.all.count))))]
            if owned.contains(choice) { arm(choice) } else { NSSound(named: "Basso")?.play() }
            return
        }
        guard let grip = grip(at: point) else { return }
        if event.clickCount == 2 && grip == .handle {
            reset()
        } else if event.modifierFlags.contains(.option) {
            window?.performDrag(with: event)
        } else {
            grab(grip, at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) { heldAt = convert(event.locationInWindow, from: nil) }

    override func mouseUp(with event: NSEvent) { held = nil }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for choice in Weapon.all {
            let item = menu.addItem(withTitle: owned.contains(choice) ? choice.label : "🔒 \(choice.label) · \(choice.price) gold in the shop", action: #selector(pickWeapon(_:)), keyEquivalent: "")
            item.target = self
            item.tag = choice.index
            item.state = choice == weapon ? .on : .off
            item.isEnabled = owned.contains(choice)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: isVibing ? "Back to smashing (F3)" : "Vibe (F3)", action: #selector(toggleVibe), keyEquivalent: "").target = self
        for (title, bubbles) in [("🫧 Soap bubbles", true), ("🚬 Smoke break", false)] {
            let item = menu.addItem(withTitle: "    " + title, action: #selector(pickVibe(_:)), keyEquivalent: "")
            item.target = self
            item.tag = bubbles ? 1 : 0
            item.state = blowsBubbles == bubbles ? .on : .off
        }
        let shaking = menu.addItem(withTitle: "Screen shake", action: #selector(toggleShake), keyEquivalent: "")
        shaking.target = self
        shaking.state = shakesScreen ? .on : .off
        if isDev { menu.addItem(withTitle: "🛠 Open shop", action: #selector(devShop), keyEquivalent: "").target = self }
        menu.addItem(withTitle: "Reset", action: #selector(reset), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Boink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func swing(handleAcceleration: CGVector, dt: CGFloat) {
        // A bat swung from its handle: the hand's acceleration whips the barrel around behind it.
        let reach = weapon.length * weapon.balance
        let torque = -((gravity + handleAcceleration.dy) * sin(angle) + handleAcceleration.dx * cos(angle)) / reach
        spin += (torque - weapon.damping * spin) * dt
        angle += spin * dt
    }

    func moveBat() {
        let previousVelocity = handleVelocity
        let target = CGPoint(x: slimeGrip.x + grabOffset.dx, y: slimeGrip.y + grabOffset.dy)
        switch held {
        case .handle:
            let next = CGPoint(x: clamp(target.x, 20, bounds.width - 20), y: clamp(target.y, ground + penguinReach, bounds.maxY - 10))
            handleVelocity = CGVector(dx: (next.x - handleAt.x) / tick, dy: (next.y - handleAt.y) / tick)
            handleAt = next
        case .barrel:
            let aimed = nearest(angleFromDown(target.x - handleAt.x, target.y - handleAt.y), to: angle)
            spin = spin * 0.4 + (aimed - angle) / tick * 0.6
            angle = aimed
            handleVelocity = .zero
        case nil:
            // Let go in mid-air, the penguin drops back to the ground.
            handleVelocity = CGVector(dx: handleVelocity.dx * 0.9, dy: handleAt.y > ground + penguinReach ? handleVelocity.dy - 900 * tick : 0)
            handleAt = CGPoint(x: clamp(handleAt.x + handleVelocity.dx * tick, 10, bounds.width - 10),
                               y: max(ground + penguinReach, min(bounds.maxY - 10, handleAt.y + (handleVelocity.dy - 900 * tick) * tick)))
        }

        guard held != .barrel else { restOnFloor(); return }
        let acceleration = CGVector(dx: clamp((handleVelocity.dx - previousVelocity.dx) / tick, -30000, 30000),
                                    dy: clamp((handleVelocity.dy - previousVelocity.dy) / tick, -30000, 30000))
        for _ in 0..<substeps { swing(handleAcceleration: acceleration, dt: tick / CGFloat(substeps)) }
        restOnFloor()
    }

    func restOnFloor() {
        let room = (handleAt.y - ground - 2) / weapon.length
        guard room < 1 else { return }
        let limit = acos(clamp(room, -1, 1))
        let wrapped = atan2(sin(angle), cos(angle))
        guard abs(wrapped) < limit else { return }
        let side: CGFloat = wrapped == 0 ? penguinFacing : (wrapped > 0 ? 1 : -1)
        angle += side * limit - wrapped
        spin = -spin * 0.25
    }

    @objc func reset() {
        handleAt = CGPoint(x: bounds.midX - 150, y: ground + penguinReach)
        angle = 0.9
        spin = 0
        handleVelocity = .zero
        held = nil
        boinks = 0
        dodges = 0
        score = 0
        combo = 0
        bestCombo = 0
        kos = 0
        slimedAt = -1000
        jellyHits = 0
        slices = 0
        cut = nil
        bursts = []
        penguinHurtAt = -1000
        particles = []
        popups = []
        swoosh = []
        gameOverAt = -1000
        gold = isDev ? devGold : 0
        owned = [.bat]
        ranks = [:]
        tiers = [:]
        isShopping = false
        weapon = .bat
        countIn(to: 1)
        NSSound(named: "Bottle")?.play()
    }

    func startLevel(_ next: Int) {
        level = next
        levelAt = clock
        let size = levelSize(next)
        let margin = blobRadius * size + 8
        // They drop in from random heights so they land one by one instead of lining up.
        blobs = (0..<levelSlimes(next)).map { _ in
            var blob = Blob(size: size, health: levelHealth(next), at: CGFloat.random(in: margin...(bounds.width - margin)))
            let ceiling = max(100, bounds.height - ground - (blobBottom + 2 + blobTop) * size - 10)
            blob.lift = CGFloat.random(in: (ceiling * 0.6)...ceiling)
            return blob
        }
        current = 0
        banner("LEVEL \(next)", color: .systemBlue)
    }

    func clearLevel() {
        clearedAt = clock
        let bonus = Int(timeLeft * 100) * level
        award(bonus, at: CGPoint(x: bounds.midX, y: ground + 120), color: .systemGreen, size: 30, label: "TIME BONUS")
        earn(5 + Int(timeLeft), at: CGPoint(x: bounds.midX, y: ground + 150))
        banner("LEVEL \(level) CLEAR!", color: .systemGreen)
        NSSound(named: "Glass")?.play()
    }

    func timeUp() {
        gameOverAt = clock
        held = nil
        banner("TIME'S UP!", color: .systemRed)
        NSSound(named: "Basso")?.play()
    }

    // Power 0 is a tap at boinkSpeed, 1 is twice as fast, up to 3 for a full-on smash.
    func boink(velocity: CGVector, slicingAt contact: CGPoint? = nil) {
        guard !isKO else { return }
        let speed = hypot(velocity.dx, velocity.dy)
        lastHitWasSlice = contact != nil
        lastHitAt = clock
        hitWeapon = weapon
        if let contact {
            slices += 1
            slicedAt = clock
            cutWeapon = weapon
            let length = max(speed, 0.001)
            cut = Cut(point: contact, direction: CGVector(dx: velocity.dx / length, dy: velocity.dy / length))
        } else {
            boinks += 1
        }
        let wasAirborne = isAirborne
        if wasAirborne { me.airHits += 1 }
        combo = isComboLive ? combo + 1 : 1
        bestCombo = max(bestCombo, combo)
        me.boinkedAt = clock
        me.impact = speed / boinkSpeed
        me.boinkPower = min(3, max(0, me.impact - 1) * 1.5)
        let airBonus = 1 + 0.25 * CGFloat(me.airHits)
        award(Int(CGFloat(hitPoints * combo) * airBonus), at: barrel, color: .systemYellow)
        let isSmash = contact == nil && weapon.isSmash
        let damage = min(50, 3 * me.impact * me.impact) * airBonus * (1 + 0.1 * CGFloat(combo - 1)) * (weapon == .axe ? chopPower : 1) * (1 + 0.15 * CGFloat(rank(.power))) * (1 + forgeBoost * CGFloat(tier(weapon)))
        me.health -= damage
        if me.airHits >= 1 {
            popups.append(Popup(text: "AIR x\(me.airHits)", position: CGPoint(x: me.jellyX, y: head.y + 90), born: clock, color: .systemTeal, size: 16 + 2 * CGFloat(min(me.airHits, 6))))
        }
        if isSmash {
            smashAway(velocity, wasAirborne: wasAirborne)
        } else {
            launch(velocity, wasAirborne: wasAirborne, scale: contact == nil ? 1.25 : 0.8)
        }
        splash(at: barrel, count: Int(10 + 8 * me.boinkPower) + 4 * combo, force: 260 + 120 * me.boinkPower)
        shake = max(shake, 4 + 3 * me.boinkPower + 2 * CGFloat(combo))
        // A blade passes straight through, so slices get only a blink of hit-stop.
        hitstop = lastHitWasSlice ? 1 : Int(2 + me.boinkPower) + min(combo, 3)
        if isStunned {
            award(hitPoints * combo, at: CGPoint(x: barrel.x, y: barrel.y + 24), color: .systemOrange, label: "COUNTER")
            banner(lastHitWasSlice ? "COUNTER SLICE!" : "COUNTER \(weapon.hit)!", color: .systemOrange)
        } else if combo >= 2 {
            let words = comboWords[min(combo, comboWords.count - 1)]
            banner(words.replacingOccurrences(of: "BOINK", with: lastHitWasSlice ? "SLICE" : weapon.hit),
                   color: [.systemOrange, .systemRed, .systemPink, .systemPurple][min(combo - 2, 3)])
        }
        if !isStunned { me.rage = min(1, me.rage + 0.16 + 0.05 * me.boinkPower + (combo >= 3 ? 0.08 : 0)) }
        penguinCheerAt = clock
        let contactPoint = contact ?? barrel
        bursts.append(Burst(point: contactPoint, born: clock, size: 26 + 14 * me.boinkPower, isRing: false,
                            color: weapon == .saber ? .systemOrange : weapon == .fish ? .systemBlue : lastHitWasSlice ? .systemCyan : .systemYellow))
        bursts.append(Burst(point: bodyCenter, born: clock, size: (1 + 0.4 * me.boinkPower) * me.size, isRing: true))
        if lastHitWasSlice {
            // A blade goes straight through: no bounce, no tumble, just a clean split.
            me.weird = []
            me.jellySpeed += clamp(velocity.dx * 0.15, -150, 150)
            me.jelly.wobble(toward: CGVector(dx: 0, dy: 1), strength: 0.6)
            if let cut { sprayAlong(cut, count: 26 + Int(12 * me.boinkPower)) }
            NSSound(named: weapon == .saber ? "Submarine" : "Glass")?.play()
        } else {
            me.jelly.dent(toward: CGVector(dx: contactPoint.x - bodyCenter.x, dy: contactPoint.y - bodyCenter.y), strength: 1.6 + 0.5 * me.boinkPower)
            if weapon == .fish {
                for _ in 0..<18 {
                    particles.append(Particle(position: contactPoint, velocity: CGVector(dx: CGFloat.random(in: -260...260), dy: CGFloat.random(in: 80...380)),
                                              life: 0, span: CGFloat.random(in: 0.4...0.9), size: CGFloat.random(in: 2...4),
                                              color: NSColor.systemCyan.withAlphaComponent(0.85)))
                }
            }
            me.weird = Set(Weird.allCases.shuffled().prefix(Int(me.boinkPower.rounded())))
            spin *= -0.6
            if !isSmash { me.jellySpeed += clamp(velocity.dx * 0.5, -520, 520) }
            me.jelly.wobble(toward: CGVector(dx: velocity.dx * 0.3, dy: max(abs(velocity.dy), 1)), strength: 1.2 + 0.6 * me.boinkPower)
            NSSound(named: weapon == .fish ? "Bottle" : "Frog")?.play()
        }
        if me.boinkPower >= 2 || combo >= 3 { NSSound(named: "Funk")?.play() }
        if isSmash { shockwave(from: me.jellyX, damage: damage) }
        if me.health <= 0 {
            knockOut()
        } else if !isSmash {
            split()
        }
    }

    // A smash hands the swing's momentum to the jelly: it flies, slides and rebounds the way it was hit, lighter slimes further.
    func smashAway(_ velocity: CGVector, wasAirborne: Bool) {
        let push = weapon.knock * (1 + 0.2 * CGFloat(rank(.heft))) / me.size
        me.tumbling = true
        me.jellySpeed = clamp(me.jellySpeed * 0.3 + velocity.dx * push, -maxKnock, maxKnock)
        if velocity.dy < 0 && wasAirborne {
            me.liftSpeed = min(me.liftSpeed, velocity.dy * push)
        } else if velocity.dy < 0 {
            me.liftSpeed = min(maxLaunch, -velocity.dy * push * 0.7)
        } else {
            me.liftSpeed = min(maxLaunch, max(me.liftSpeed, 0) + velocity.dy * push * 0.8 + (wasAirborne ? 300 : 0))
        }
    }

    func chain() {
        combo = isComboLive ? combo + 1 : 1
        bestCombo = max(bestCombo, combo)
        lastHitAt = clock
    }

    func splat(_ speed: CGFloat) {
        let side: CGFloat = me.jellyX < bounds.midX ? -1 : 1
        let damage = speed * 0.03
        chain()
        me.health -= damage
        me.shakenAt = clock
        me.jelly.dent(toward: CGVector(dx: side, dy: 0), strength: min(2.5, speed / 450))
        shake = max(shake, speed / 150)
        hitstop = max(hitstop, 3)
        award(Int(damage * 12) * combo, at: CGPoint(x: me.jellyX, y: jellyTop + 20), color: .systemPink, label: "SPLAT")
        earn(1, at: CGPoint(x: me.jellyX, y: jellyTop + 20))
        splash(at: CGPoint(x: me.jellyX + side * radius, y: bodyCenter.y), count: 16, force: 260)
        NSSound(named: "Bottle")?.play()
        if me.health <= 0 { knockOut() }
    }

    // A tumbling slime knocks into the others like a bowling ball, trading momentum by size and hurting both.
    func bowl(_ a: Int, _ b: Int, closing: CGFloat) {
        let (ma, mb) = (blobs[a].size * blobs[a].size, blobs[b].size * blobs[b].size)
        let (va, vb) = (blobs[a].jellySpeed, blobs[b].jellySpeed)
        let bounce: CGFloat = 0.9
        blobs[a].jellySpeed = (ma * va + mb * vb + mb * bounce * (vb - va)) / (ma + mb)
        blobs[b].jellySpeed = (ma * va + mb * vb + ma * bounce * (va - vb)) / (ma + mb)
        chain()
        let damage = closing * 0.02
        for i in [a, b] {
            current = i
            me.tumbling = true
            me.shakenAt = clock
            me.health -= damage
            if !isAirborne { me.liftSpeed = closing * 0.25 }
            me.jelly.dent(toward: CGVector(dx: i == a ? 1 : -1, dy: 0), strength: min(2, closing / 500))
        }
        let spot = CGPoint(x: (blobs[a].jellyX + blobs[b].jellyX) / 2, y: ground + blobs[b].lift + 60)
        award(Int(damage * 20) * combo, at: spot, color: .systemOrange, label: "BOWLED")
        earn(1, at: spot)
        bursts.append(Burst(point: spot, born: clock, size: 20 + closing / 60, isRing: false, color: .systemOrange))
        shake = max(shake, closing / 180)
        hitstop = max(hitstop, 2)
        NSSound(named: "Frog")?.play()
        for i in [a, b] where !blobs[i].isGone && blobs[i].health <= 0 {
            current = i
            knockOut()
        }
    }

    // A blunt smash squashes instead of splitting, and sends a shockwave along the floor that shoves, dizzies and hurts the slimes nearby.
    func shockwave(from origin: CGFloat, damage: CGFloat) {
        let struck = current
        let reach = shockReach * (1 + 0.2 * me.boinkPower) * (1 + 0.2 * CGFloat(rank(.heft)))
        for i in blobs.indices where i != struck && !blobs[i].isGone && !blobs[i].isAirborne {
            let gap = blobs[i].jellyX - origin
            guard abs(gap) < reach else { continue }
            let falloff = 1 - abs(gap) / reach
            current = i
            me.health -= damage * shockShare * falloff
            me.shakenAt = clock
            me.jellySpeed += (gap >= 0 ? 1 : -1) * 320 * falloff
            me.liftSpeed = 300 * falloff
            me.jelly.dent(toward: CGVector(dx: -gap, dy: -20), strength: 1.4 * falloff)
            if me.health <= 0 { knockOut() }
        }
        current = struck
        bursts.append(Burst(point: CGPoint(x: origin, y: ground + 6), born: clock, size: reach / 110, isRing: true))
    }

    // A blade's cut breaks a slime into two smaller ones that fly apart, carrying its damage; the smallest ones, or any past the crowd limit, just have to be beaten.
    func split() {
        guard me.size >= minSplitSize, blobs.count < maxSlimes else { return }
        let parent = me
        let size = parent.size * splitShrink
        let halves = [-1, 1].map { (side: CGFloat) -> Blob in
            let x = clamp(parent.jellyX + side * blobRadius * size * 0.6, blobRadius * size + 8, bounds.width - blobRadius * size - 8)
            var half = Blob(size: size, health: parent.maxHealth, at: x)
            half.health = parent.health
            half.rage = parent.rage * 0.5
            half.lift = parent.lift
            half.liftSpeed = max(parent.liftSpeed, 0) + 480
            half.jellySpeed = parent.jellySpeed * 0.5 + side * 280
            half.boinkedAt = clock
            half.boinkPower = parent.boinkPower
            half.impact = parent.impact
            half.weird = parent.weird
            half.airHits = parent.airHits
            half.jelly.wobble(toward: CGVector(dx: side, dy: 0.5), strength: 1.4)
            return half
        }
        blobs[current] = halves[0]
        blobs.append(halves[1])
        popups.append(Popup(text: "SPLIT!", position: CGPoint(x: parent.jellyX, y: head.y + 60), born: clock, color: .systemCyan, size: 18))
        NSSound(named: "Pop")?.play()
    }

    // Soft taps leave it on the ground; a hard hit pops it up, and any hit in the air keeps it up, or spikes it down.
    func launch(_ velocity: CGVector, wasAirborne: Bool, scale: CGFloat) {
        let pop = max(0, me.impact - 1.1)
        guard pop > 0 || wasAirborne else { return }
        if wasAirborne && velocity.dy < -abs(velocity.dx) {
            me.liftSpeed = min(me.liftSpeed, velocity.dy * 0.7)
            return
        }
        let up = (420 * pop + 0.35 * max(velocity.dy, 0) + (wasAirborne ? 380 : 0)) * scale
        me.liftSpeed = min(maxLaunch, max(me.liftSpeed, 0) + up)
    }

    func fly() {
        guard isAirborne else { return }
        me.lift += me.liftSpeed * tick
        me.liftSpeed -= airGravity * tick
        if me.lift > ceilingLift {
            me.lift = ceilingLift
            me.liftSpeed = -abs(me.liftSpeed) * bounceKeep
        }
        guard me.lift <= 0 else { return }
        me.lift = 0
        let fall = -me.liftSpeed
        if fall > bounceFrom {
            me.liftSpeed = fall * bounceKeep
            me.jellySpeed *= 0.92
            me.jelly.wobble(toward: CGVector(dx: 0, dy: 1), strength: min(2.2, fall / 400))
            if fall > 600 { shake = max(shake, fall / 250) }
            NSSound(named: "Bottle")?.play()
        } else {
            me.liftSpeed = 0
            if me.airHits >= 2 { banner("JUGGLE x\(me.airHits)!", color: .systemTeal) }
            me.airHits = 0
        }
    }

    func whirlPull() {
        guard isWhirling, !me.isGone else { return }
        let toward = handle.x - me.jellyX
        guard abs(toward) < whirlReach * 2.5, abs(toward) > 10 else { return }
        // Nudging the position directly keeps a fleeing slime from simply outrunning the wind.
        let margin = radius + 8
        me.jellyX = clamp(me.jellyX + (toward > 0 ? 1 : -1) * min(abs(toward), 280 * tick), margin, bounds.width - margin)
        if !isAirborne && abs(toward) < whirlReach * 1.5 { me.liftSpeed = max(me.liftSpeed, 220) }
    }

    func knockOut() {
        kos += 1
        me.health = 0
        me.weird = []
        me.rage = 0
        me.fury = .idle
        me.koAt = clock
        award(Int(500 * me.size) * combo, at: CGPoint(x: me.jellyX, y: ground - 70), color: .systemRed, size: 30, label: "K.O.")
        earn(5 + level, at: CGPoint(x: me.jellyX, y: ground - 70))
        let isLast = blobs.allSatisfy { $0.isGone }
        if isLast { banner("K.O.!!", color: .systemRed) }
        splash(at: head, count: isLast ? 70 : 30, force: 520)
        shake = max(shake, isLast ? 18 : 7)
        hitstop = isLast ? 10 : 2
        NSSound(named: "Hero")?.play()
    }

    func award(_ points: Int, at spot: CGPoint, color: NSColor, size: CGFloat = 20, label: String = "") {
        score += points
        if score > best {
            best = score
            if !isTrial && !isDev { UserDefaults.standard.set(best, forKey: "bestScore") }
        }
        let text = label.isEmpty ? "+\(points)" : "+\(points) \(label)"
        let stacked = CGFloat(popups.count)
        let spot = CGPoint(x: spot.x + (popups.count % 2 == 0 ? 30 : -30), y: spot.y + stacked * 24)
        popups.append(Popup(text: text, position: spot, born: clock, color: color, size: size))
        if popups.count > 24 { popups.removeFirst(popups.count - 24) }
    }

    func earn(_ amount: Int, at spot: CGPoint) {
        let amount = Int((CGFloat(amount) * (1 + 0.25 * CGFloat(rank(.greed)))).rounded())
        gold += amount
        popups.append(Popup(text: "+\(amount) 🪙", position: CGPoint(x: spot.x, y: spot.y + 34), born: clock, color: .systemYellow, size: 18))
    }

    var wares: [Ware] { Weapon.all.map { owned.contains($0) ? .forge($0) : .weapon($0) } + Upgrade.allCases.map { .upgrade($0) } }

    func price(_ ware: Ware) -> Int? {
        switch ware {
        case .weapon(let choice): return owned.contains(choice) ? nil : choice.price
        case .forge(let choice): return tier(choice) + 1 < choice.tierNames.count ? choice.forgePrice(toTier: tier(choice) + 1) : nil
        case .upgrade(let upgrade): return rank(upgrade) >= maxRank ? nil : upgrade.basePrice * (rank(upgrade) + 1)
        }
    }

    func buy(_ ware: Ware) {
        guard let cost = price(ware), cost <= gold else {
            NSSound(named: "Basso")?.play()
            return
        }
        if !isDev { gold -= cost }
        switch ware {
        case .weapon(let choice):
            owned.insert(choice)
            arm(choice)
        case .forge(let choice):
            tiers[choice, default: 0] += 1
            arm(choice)
            banner(choice.tierNames[tier(choice)].uppercased() + "!", color: .systemYellow)
        case .upgrade(let upgrade):
            ranks[upgrade, default: 0] += 1
        }
        NSSound(named: "Purr")?.play()
    }

    func openShop() {
        isShopping = true
        nextLevel = level + 1
    }

    @objc func devShop() {
        blobs = []
        countdownAt = -1000
        gameOverAt = -1000
        openShop()
    }

    var goldText: String { isDev ? "∞" : "\(gold)" }

    var devSteps: [(frame: NSRect, step: Int)] {
        guard isDev else { return [] }
        let size = NSSize(width: 44, height: nextFrame.height)
        return [(-10, -100), (-1, -52), (1, 8), (10, 56)].map { step, offset in
            let x = step < 0 ? nextFrame.minX + CGFloat(offset) : nextFrame.maxX + CGFloat(offset)
            return (NSRect(origin: CGPoint(x: x, y: nextFrame.minY), size: size), step)
        }
    }

    func leaveShop() {
        isShopping = false
        countIn(to: nextLevel)
    }

    var isCountingDown: Bool { countdownAt > -1000 }

    var countLeft: Int { countFrom - Int(age(countdownAt)) }

    func countIn(to next: Int) {
        blobs = []
        upcoming = next
        countdownAt = clock
        shownCount = 0
    }

    func countDown() {
        if countLeft <= 0 {
            countdownAt = -1000
            startLevel(upcoming)
            banner("GO!", color: .systemGreen)
            NSSound(named: "Hero")?.play()
        } else if countLeft != shownCount {
            shownCount = countLeft
            NSSound(named: "Tink")?.play()
        }
    }

    var shopFrame: NSRect { NSRect(x: bounds.midX - 270, y: bounds.midY - 230, width: 560, height: 466) }

    func wareFrame(_ row: Int) -> NSRect { NSRect(x: shopFrame.minX + 16, y: shopFrame.maxY - 112 - CGFloat(row) * 36, width: shopFrame.width - 32, height: 30) }

    var nextFrame: NSRect { NSRect(x: shopFrame.midX - 100, y: shopFrame.minY + 14, width: 200, height: 36) }

    func banner(_ text: String, color: NSColor) {
        bannerText = text
        bannerColor = color
        bannerAt = clock
    }

    func splash(at spot: CGPoint, count: Int, force: CGFloat) {
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0.15 * .pi...0.85 * .pi) + (Bool.random() ? 0 : .pi * CGFloat.random(in: -0.2...0.2))
            let speed = force * CGFloat.random(in: 0.4...1.1)
            let tone = CGFloat.random(in: 0...1)
            particles.append(Particle(
                position: spot,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                life: 0, span: CGFloat.random(in: 0.6...1.3), size: CGFloat.random(in: 2.5...6),
                color: jellyDeep.blended(withFraction: tone, of: jellyBright) ?? jellyBright))
        }
        if particles.count > 400 { particles.removeFirst(particles.count - 400) }
    }

    func sprayAlong(_ cut: Cut, count: Int) {
        for i in 0..<count {
            let along = CGFloat.random(in: -60...60)
            let side: CGFloat = i % 2 == 0 ? 1 : -1
            let speed = CGFloat.random(in: 120...340)
            particles.append(Particle(
                position: CGPoint(x: cut.point.x + cut.direction.dx * along, y: cut.point.y + cut.direction.dy * along),
                velocity: CGVector(dx: cut.normal.dx * speed * side + cut.direction.dx * 80, dy: cut.normal.dy * speed * side + 160),
                life: 0, span: CGFloat.random(in: 0.5...1.1), size: CGFloat.random(in: 2...4.5),
                color: jellyBright.blended(withFraction: CGFloat.random(in: 0...0.5), of: .white) ?? jellyBright))
        }
    }

    func dodge() {
        dodges += 1
        if combo >= 2 { popups.append(Popup(text: "combo broken!", position: CGPoint(x: me.jellyX, y: head.y + 60), born: clock, color: .systemTeal, size: 15)) }
        combo = 0
        me.dodgedAt = clock
        NSSound(named: "Tink")?.play()
    }

    func checkHit() {
        guard !isKO && !isEnraged else { me.isNearMiss = false; return }
        let velocity = CGVector(dx: (barrel.x - lastBarrel.x) / tick, dy: (barrel.y - lastBarrel.y) / tick)
        let speed = hypot(velocity.dx, velocity.dy)
        let floor = ground + me.lift
        let top = jellyTop
        let across = abs(barrel.x - me.jellyX)
        // A blunt weapon lands with its whole heavy end, not just the very tip.
        let isTouching = (0...6).contains { i in
            let t = 0.55 + 0.075 * CGFloat(i)
            let point = CGPoint(x: handle.x + (barrel.x - handle.x) * t, y: handle.y + (barrel.y - handle.y) * t)
            return abs(point.x - me.jellyX) < radius * 0.9 + barrelRadius && point.y < top + barrelRadius && point.y > floor - barrelRadius
        }
        let isClose = across < radius + dodgeMargin && barrel.y < top + dodgeMargin && barrel.y > floor - 10

        let blade = (0...10).map { i -> CGPoint in
            let t = 0.3 + 0.07 * CGFloat(i)
            return CGPoint(x: handle.x + (barrel.x - handle.x) * t, y: handle.y + (barrel.y - handle.y) * t)
        }
        let contact = blade.first { abs($0.x - me.jellyX) < radius * 0.85 && $0.y > floor + 4 && $0.y < top - 4 }

        let offset = CGVector(dx: me.jellyX - handle.x, dy: bodyCenter.y - handle.y)
        let gap = max(hypot(offset.dx, offset.dy), 0.001)
        // A dodge only counts once a fast swing has passed close by and gone again without landing.
        if isWhirling && gap < whirlReach + radius * 0.6 && sinceBoink > 0.4 {
            // The whirlwind hits along its spin, with a lift so chopped slimes stay up for the next pass.
            let swirl = clamp(spin * whirlReach, -1000, 1000)
            boink(velocity: CGVector(dx: -offset.dy / gap * swirl, dy: offset.dx / gap * swirl + 350))
            me.isNearMiss = false
        } else if weapon.isBlade, let contact, speed > sliceSpeed, sinceBoink > 0.35 {
            boink(velocity: velocity, slicingAt: contact)
            me.isNearMiss = false
        } else if weapon.isBlunt && speed > boinkSpeed && isTouching && sinceBoink > 0.4 {
            boink(velocity: velocity)
            me.isNearMiss = false
        } else if isClose {
            if speed > boinkSpeed && !isDizzy && sinceBoink > 1 { me.isNearMiss = true }
        } else if me.isNearMiss {
            me.isNearMiss = false
            if age(me.dodgedAt) > 1 && !me.tumbling { dodge() }
        }
    }

    func flee() {
        let margin = radius + 8
        let threatX = barrel.x
        let distance = hypot(me.jellyX - threatX, head.y - barrel.y)
        let wasScared = me.isScared
        me.isScared = distance < fleeRange && !isDizzy && !isKO && me.fury == .idle
        if me.isScared && !wasScared { me.scaredAt = clock }

        if me.fury != .idle { return }

        var target: CGFloat = 0
        if isAirborne {
            me.jellySpeed *= 0.995
        } else if isDizzy || isKO {
            me.jellySpeed *= me.tumbling ? tumbleFriction : 0.9
        } else if isDashing {
            target = me.dashDirection * dashSpeed
        } else if me.isScared {
            let away: CGFloat = me.jellyX == threatX ? (me.jellyX < bounds.midX ? 1 : -1) : (me.jellyX > threatX ? 1 : -1)
            let room = away > 0 ? bounds.width - margin - me.jellyX : me.jellyX - margin
            if room < 6 {
                me.corneredFor += tick
                me.rage = min(1, me.rage + 0.22 * tick)
                // Pinned against a wall too long, it makes a break for it right under the bat.
                if me.corneredFor > corneredBeforeDash {
                    me.dashDirection = -away
                    me.dashUntil = clock + dashFor
                    me.corneredFor = 0
                    NSSound(named: "Pop")?.play()
                }
            } else {
                me.corneredFor = 0
                target = away * fleeSpeed * (isSore ? 1.25 : 1)
            }
        } else {
            me.corneredFor = 0
        }

        if !isDizzy && !isKO && !isAirborne {
            let previous = me.jellySpeed
            me.jellySpeed += (target - me.jellySpeed) * min(1, tick * 8)
            me.jelly.slosh(acceleration: (me.jellySpeed - previous) / tick)
        }

        me.jellyX += me.jellySpeed * tick
        let wallKeep: CGFloat = isAirborne || me.tumbling ? wallBounce : 0.3
        let wallSpeed = abs(me.jellySpeed)
        let hitWall = me.jellyX < margin || me.jellyX > bounds.width - margin
        if me.jellyX < margin { me.jellyX = margin; me.jellySpeed = abs(me.jellySpeed) * wallKeep }
        if me.jellyX > bounds.width - margin { me.jellyX = bounds.width - margin; me.jellySpeed = -abs(me.jellySpeed) * wallKeep }
        if hitWall && me.tumbling && wallSpeed > splatSpeed && !me.isGone { splat(wallSpeed) }
        if me.tumbling && !isAirborne && abs(me.jellySpeed) < 80 { me.tumbling = false }
    }

    func meanSegmentDistance(from point: CGPoint) -> CGFloat {
        let dx = barrel.x - handle.x
        let dy = barrel.y - handle.y
        let t = clamp(((point.x - handle.x) * dx + (point.y - handle.y) * dy) / max(dx * dx + dy * dy, 1), 0, 1)
        return hypot(point.x - (handle.x + dx * t), point.y - (handle.y + dy * t))
    }

    func rampage() {
        let margin = radius + 8
        switch me.fury {
        case .idle:
            if age(me.boinkedAt) > 4 && me.rage < 1 { me.rage = max(0, me.rage - 0.03 * tick) }
            if me.rage >= 1 && !isDizzy && !isKO && !isAirborne {
                me.fury = .windup
                me.furyAt = clock
                me.jellySpeed = 0
                NSSound(named: "Basso")?.play()
            }
        case .windup:
            me.jellySpeed *= 0.8
            if age(me.furyAt) > windupFor {
                if abs(barrel.x - me.jellyX) < leapReach {
                    me.fury = .leap
                    me.didLeapHit = false
                    me.leapSpeed = clamp((barrel.x - me.jellyX) / leapTime, -900, 900)
                    me.liftSpeed = clamp((barrel.y - ground - 40 + 0.5 * leapGravity * leapTime * leapTime) / leapTime, 500, 1400)
                    me.jelly.wobble(toward: CGVector(dx: 0, dy: -1), strength: 1.5)
                    NSSound(named: "Submarine")?.play()
                } else {
                    me.fury = .spit
                    let mouthSpot = CGPoint(x: me.jellyX, y: ground + me.lift + (blobBottom + 2 + blobTop * 0.4) * me.size)
                    let flight = max(0.35, abs(barrel.x - mouthSpot.x) / spitSpeed)
                    let rise = (barrel.y - mouthSpot.y + 0.5 * spitGravity * flight * flight) / flight
                    me.slime = Slime(position: mouthSpot, velocity: CGVector(dx: (barrel.x - mouthSpot.x) / flight, dy: rise))
                    NSSound(named: "Blow")?.play()
                }
                me.furyAt = clock
                me.rage = 0.25
            }
        case .leap:
            me.jellyX = clamp(me.jellyX + me.leapSpeed * tick, margin, bounds.width - margin)
            me.lift += me.liftSpeed * tick
            me.liftSpeed -= leapGravity * tick
            let body = CGPoint(x: me.jellyX, y: ground + me.lift + (blobBottom + 24) * me.size)
            if !me.didLeapHit && (hypot(barrel.x - body.x, barrel.y - body.y) < 62 * me.size || meanSegmentDistance(from: body) < 40 * me.size) {
                smashBat()
            }
            if me.lift <= 0 && me.liftSpeed < 0 {
                me.lift = 0
                me.liftSpeed = 0
                me.jelly.wobble(toward: CGVector(dx: 0, dy: 1), strength: 2.2)
                shake = max(shake, 6)
                if me.didLeapHit {
                    me.fury = .idle
                } else {
                    me.fury = .stunned
                    me.furyAt = clock
                    popups.append(Popup(text: "faceplant!", position: CGPoint(x: me.jellyX, y: head.y + 40), born: clock, color: .systemOrange, size: 17))
                    NSSound(named: "Pop")?.play()
                }
            }
        case .spit:
            if age(me.furyAt) > 0.45 { me.fury = .idle }
        case .stunned:
            me.jellySpeed *= 0.85
            if age(me.furyAt) > stunFor { me.fury = .idle }
        }

        if var blob = me.slime {
            blob.velocity.dy -= spitGravity * tick
            blob.position.x += blob.velocity.dx * tick
            blob.position.y += blob.velocity.dy * tick
            if meanSegmentDistance(from: blob.position) < 14 {
                me.slime = nil
                slimeBat()
            } else if blob.position.y < ground || blob.position.x < -20 || blob.position.x > bounds.width + 20 || blob.position.y > bounds.maxY + 20 {
                me.slime = nil
                splash(at: CGPoint(x: blob.position.x, y: max(blob.position.y, ground)), count: 12, force: 160)
            } else {
                me.slime = blob
            }
        }
    }

    func punish(_ points: Int, _ label: String, bannerText: String, color: NSColor) {
        score = max(0, score - points)
        jellyHits += 1
        penguinHurtAt = clock
        combo = 0
        popups.append(Popup(text: "-\(points) \(label)", position: CGPoint(x: barrel.x, y: barrel.y + 20), born: clock, color: color, size: 22))
        banner(bannerText, color: color)
    }

    func smashBat() {
        me.didLeapHit = true
        let away: CGFloat = barrel.x >= me.jellyX ? 1 : -1
        held = nil
        spin += away * 16
        handleVelocity = CGVector(dx: handleVelocity.dx + away * 700, dy: handleVelocity.dy + 350)
        punish(500, "OUCH", bannerText: "JELLY SMASH!", color: .systemPurple)
        splash(at: barrel, count: 30, force: 380)
        shake = 16
        hitstop = 8
        NSSound(named: "Funk")?.play()
        NSSound(named: "Frog")?.play()
    }

    func slimeBat() {
        slimedAt = clock
        punish(250, "SLIMED", bannerText: "SLIMED!", color: .systemGreen)
        splash(at: barrel, count: 24, force: 200)
        shake = max(shake, 7)
        NSSound(named: "Bottle")?.play()
    }

    func updateEffects() {
        for i in particles.indices {
            particles[i].life += tick
            particles[i].velocity.dy -= 900 * tick
            particles[i].position.x += particles[i].velocity.dx * tick
            particles[i].position.y += particles[i].velocity.dy * tick
            if particles[i].position.y < ground {
                particles[i].position.y = ground
                particles[i].velocity = CGVector(dx: particles[i].velocity.dx * 0.5, dy: -particles[i].velocity.dy * 0.3)
            }
        }
        particles.removeAll { $0.life > $0.span }
        popups.removeAll { age($0.born) > 1.1 }
        bursts.removeAll { age($0.born) > 0.45 }
        shake *= 0.86

        if combo > 0 && !isComboLive { combo = 0 }
    }

    func heal() {
        if !isKO && age(lastHitAt) > healDelay { me.health = min(me.maxHealth, me.health + healPerSecond * tick) }
    }

    // Slimes on the ground shoulder each other apart instead of stacking up.
    func separate() {
        for a in blobs.indices {
            for b in blobs.indices where b > a && !blobs[a].isGone && !blobs[b].isGone {
                let reach = blobRadius * (blobs[a].size + blobs[b].size) * 0.8
                let gap = blobs[b].jellyX - blobs[a].jellyX
                let overlap = reach - abs(gap)
                guard overlap > 0 else { continue }
                let closing = (blobs[a].jellySpeed - blobs[b].jellySpeed) * (gap >= 0 ? 1 : -1)
                let isLevel = abs(blobs[a].lift - blobs[b].lift) < blobTop * (blobs[a].size + blobs[b].size) * 0.6
                if (blobs[a].tumbling || blobs[b].tumbling) && isLevel && closing > bowlSpeed { bowl(a, b, closing: closing) }
                guard !blobs[a].isAirborne && !blobs[b].isAirborne else { continue }
                let push = (gap >= 0 ? 1 : -1) * overlap / 2
                blobs[a].jellyX = clamp(blobs[a].jellyX - push, blobRadius * blobs[a].size + 8, bounds.width - blobRadius * blobs[a].size - 8)
                blobs[b].jellyX = clamp(blobs[b].jellyX + push, blobRadius * blobs[b].size + 8, bounds.width - blobRadius * blobs[b].size - 8)
            }
        }
    }

    func forEachBlob(_ body: () -> Void) {
        var i = 0
        while i < blobs.count {
            current = i
            body()
            i += 1
        }
    }

    func step() {
        // A short freeze on impact makes big hits land harder.
        if hitstop > 0 {
            hitstop -= 1
            shake *= 0.95
            clock += tick * 0.05
            needsDisplay = true
            return
        }
        clock += tick
        updateEffects()

        if isSlimed {
            slimeGrip = CGPoint(x: slimeGrip.x + (heldAt.x - slimeGrip.x) * 0.08, y: slimeGrip.y + (heldAt.y - slimeGrip.y) * 0.08)
            spin *= 0.93
        } else {
            slimeGrip = heldAt
        }
        moveBat()

        if !isGameOver { forEachBlob { checkHit() } }
        lastBarrel = barrel
        let rest = Jelly.restRadii(time: clock)
        forEachBlob {
            if !isGameOver { rampage() }
            whirlPull()
            fly()
            flee()
            heal()
            for _ in 0..<substeps {
                me.jelly.step(center: jellyCenter, floor: ground + me.lift, rest: rest, dt: tick / CGFloat(substeps))
            }
        }
        separate()
        forEachBlob {
            if me.isGone && age(me.koAt) > koFor { splash(at: head, count: 30, force: 300) }
        }
        let hadBlobs = !blobs.isEmpty
        blobs.removeAll { $0.isGone && age($0.koAt) > koFor }
        current = 0
        if !isGameOver {
            if isCountingDown {
                countDown()
            } else if blobs.isEmpty {
                if hadBlobs { clearLevel() } else if age(clearedAt) > 1.6 && !isShopping { openShop() }
            } else if timeLeft <= 0 {
                timeUp()
            }
        }

        swoosh.append(barrel)
        if swoosh.count > swooshLength { swoosh.removeFirst(swoosh.count - swooshLength) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isVibing {
            drawVibe()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        let jolt = NSAffineTransform()
        let jitter = shakesScreen ? shake : 0
        jolt.translateX(by: sin(clock * 97) * jitter, yBy: cos(clock * 89) * jitter * 0.6)
        jolt.concat()
        drawWorld()
        NSGraphicsContext.restoreGraphicsState()
        drawBanner()
        drawScore()
        drawShop()
        drawCountdown()
        drawGameOver()
    }

    func drawWorld() {
        drawWhirlwind()
        drawSwoosh()

        forEachBlob {
            let blob = jellyPath
            drawJellyShadow(blob)
            withJellyTransform {
                drawJellyBody(blob)
                drawFace()
            }
            drawJellyFlash()
        }
        drawPenguin()
        switch weapon {
        case .bat: drawBat()
        case .katana: drawKatana()
        case .saber: drawSaber()
        case .fish: drawFish()
        case .axe: drawAxe()
        }
        drawFlippers()
        drawBursts()
        forEachBlob { drawSpit() }
        drawSlimedBat()
        drawSlash()

        drawParticles()
        forEachBlob {
            drawHealth()
            drawCaptions()
        }
        drawPopups()
    }

    func drawSlash() {
        guard let cut else { return }
        let t = age(slicedAt)
        if cutWeapon == .saber && t < 0.6 {
            let heat = 1 - t / 0.6
            let sear = NSBezierPath()
            sear.move(to: CGPoint(x: cut.point.x - cut.direction.dx * 150, y: cut.point.y - cut.direction.dy * 150))
            sear.line(to: CGPoint(x: cut.point.x + cut.direction.dx * 150, y: cut.point.y + cut.direction.dy * 150))
            sear.lineCapStyle = .round
            sear.lineWidth = 9 * heat
            NSColor.systemOrange.withAlphaComponent(0.85 * heat).setStroke()
            sear.stroke()
        }
        guard t < 0.35 else { return }
        let fade = 1 - t / 0.35
        let flash = NSBezierPath()
        flash.move(to: CGPoint(x: cut.point.x - cut.direction.dx * 160, y: cut.point.y - cut.direction.dy * 160))
        flash.line(to: CGPoint(x: cut.point.x + cut.direction.dx * 160, y: cut.point.y + cut.direction.dy * 160))
        flash.lineCapStyle = .round
        flash.lineWidth = 14 * fade
        NSColor.systemCyan.withAlphaComponent(0.35 * fade).setStroke()
        flash.stroke()
        flash.lineWidth = 3.5 * fade
        NSColor.white.withAlphaComponent(fade).setStroke()
        flash.stroke()
    }

    func withJellyTransform(_ draw: () -> Void) {
        let t = sinceBoink
        let foot = CGPoint(x: me.jellyX, y: ground + me.lift)
        let transform = NSAffineTransform()
        transform.translateX(by: foot.x, yBy: foot.y)
        transform.scale(by: me.size)
        if !isDizzy && abs(me.jellySpeed) > 25 {
            transform.translateX(by: 0, yBy: abs(sin(clock * 15)) * min(9, abs(me.jellySpeed) / 25))
        }
        if isCornered {
            transform.translateX(by: sin(clock * 70) * 1.8, yBy: 0)
        }
        if me.fury == .windup {
            let build = age(me.furyAt) / windupFor
            transform.translateX(by: sin(clock * 90) * (2 + 4 * build), yBy: 0)
            transform.scaleX(by: 1 + 0.12 * build, yBy: 1 - 0.18 * build)
        }
        if me.fury == .leap {
            transform.scaleX(by: 0.85, yBy: 1.2)
        }
        if isStunned {
            let flat = min(1, age(me.furyAt) / 0.1) * clamp((stunFor - age(me.furyAt)) / 0.3, 0, 1)
            transform.scaleX(by: 1 + 0.35 * flat, yBy: 1 - 0.4 * flat)
        }
        if isWeird(.spin) {
            let turn = min(1, t / 1.1)
            transform.translateX(by: 0, yBy: blobBottom + 2)
            transform.rotate(byDegrees: 360 * (1 - pow(1 - turn, 3)))
            transform.translateX(by: 0, yBy: -blobBottom - 2)
        }
        if isKO {
            let flat = min(1, sinceKO / 0.12) * clamp((CGFloat(koFor) - sinceKO) / 0.5, 0, 1)
            transform.scaleX(by: 1 + 0.75 * flat, yBy: 1 - 0.72 * flat)
        } else if isDizzy {
            let squash = max(0.3, 1 - (0.3 + 0.13 * me.boinkPower) * exp(-2.5 * t) * cos(11 * t))
            transform.scaleX(by: 1 / sqrt(squash), yBy: squash)
        }
        transform.translateX(by: -foot.x, yBy: -foot.y)

        NSGraphicsContext.saveGraphicsState()
        transform.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }
}

let jellyBright = NSColor(calibratedRed: 0.62, green: 1.0, blue: 0.28, alpha: 0.86)
let jellyDeep = NSColor(calibratedRed: 0.0, green: 0.55, blue: 0.4, alpha: 0.92)
let jellyRim = NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.3, alpha: 0.95)
let wood = NSColor(calibratedRed: 0.86, green: 0.64, blue: 0.38, alpha: 1)
let woodDark = NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.18, alpha: 1)
let tape = NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.18, alpha: 1)
let steel = NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.88, alpha: 1)
let steelDark = NSColor(calibratedRed: 0.42, green: 0.46, blue: 0.54, alpha: 1)
let wrap = NSColor(calibratedRed: 0.1, green: 0.12, blue: 0.3, alpha: 1)
let brass = NSColor(calibratedRed: 0.72, green: 0.56, blue: 0.22, alpha: 1)
let ink = NSColor.black.withAlphaComponent(0.8)
let bubbles: [(x: CGFloat, speed: CGFloat, size: CGFloat, phase: CGFloat)] = [
    (-0.45, 9, 5, 0.1), (-0.15, 6, 3.5, 0.6), (0.2, 11, 4.5, 0.3), (0.5, 7, 3, 0.8), (0.05, 8, 2.5, 0.45), (-0.6, 10, 2.5, 0.9),
]

func paintJellyGradients(in box: NSRect, bright: NSColor, deep: NSColor) {
    NSGradient(starting: deep, ending: bright)?.draw(in: box, angle: 90)
    NSGradient(starting: NSColor.white.withAlphaComponent(0), ending: jellyRim.withAlphaComponent(0.55))?
        .draw(in: box.insetBy(dx: -box.width * 0.12, dy: -box.height * 0.2), relativeCenterPosition: NSPoint(x: -0.1, y: 0.15))
    NSGradient(starting: NSColor(calibratedRed: 0.85, green: 1, blue: 0.6, alpha: 0.45), ending: NSColor.white.withAlphaComponent(0))?
        .draw(in: NSBezierPath(ovalIn: NSRect(x: box.minX + box.width * 0.1, y: box.minY - 10, width: box.width * 0.8, height: min(box.height * 0.45, 50))), relativeCenterPosition: .zero)
}

// Painting three gradients per slime every frame is the main drawing cost, so the usual green body is painted once and stretched.
let jellyTexture: CGImage = {
    let size = NSSize(width: blobRadius * 2, height: blobTop + blobBottom)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    paintJellyGradients(in: NSRect(origin: .zero, size: size), bright: jellyBright, deep: jellyDeep)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.cgImage!
}()

// Emoji are slow to lay out, and every angry slime shows this one each frame.
let rageIcon: NSImage = {
    let face = "😡" as NSString
    let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
    let size = face.size(withAttributes: style)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    face.draw(at: .zero, withAttributes: style)
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(bitmap)
    return image
}()

func shifted(_ color: NSColor, by turn: CGFloat) -> NSColor {
    let base = color.usingColorSpace(.deviceRGB) ?? color
    let hue = (base.hueComponent + turn).truncatingRemainder(dividingBy: 1)
    return NSColor(hue: hue, saturation: min(1, base.saturationComponent + 0.15), brightness: base.brightnessComponent, alpha: base.alphaComponent)
}

// Dizzy slimes each orbit up to nine stars; laying them out as text every frame was a big share of a crowded frame.
let starShape: NSBezierPath = {
    let star = NSBezierPath()
    for i in 0..<10 {
        let a = .pi / 2 + CGFloat(i) * .pi / 5
        let r: CGFloat = i % 2 == 0 ? 7 : 3
        let point = CGPoint(x: cos(a) * r, y: sin(a) * r)
        if i == 0 { star.move(to: point) } else { star.line(to: point) }
    }
    star.close()
    star.lineWidth = 1.2
    star.lineJoinStyle = .round
    return star
}()

func drawStar(at point: CGPoint) {
    let star = starShape.copy() as! NSBezierPath
    star.transform(using: AffineTransform(translationByX: point.x, byY: point.y))
    NSColor.white.setStroke()
    star.stroke()
    NSColor.systemYellow.setFill()
    star.fill()
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

func drawText(_ text: String, at point: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .black, within room: CGFloat = .infinity) {
    func style(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .strokeColor: NSColor.white.withAlphaComponent(color.alphaComponent),
            .strokeWidth: -1.5,
        ]
    }
    let string = text as NSString
    let natural = string.size(withAttributes: style(size)).width
    let attributes = style(natural > room - 16 ? size * (room - 16) / natural : size)
    let width = string.size(withAttributes: attributes).width
    let x = room.isFinite ? clamp(point.x - width / 2, 8, room - width - 8) : point.x - width / 2
    string.draw(at: CGPoint(x: x, y: point.y), withAttributes: attributes)
}

extension BoinkView {
    var rainbowTurn: CGFloat { isWeird(.rainbow) ? sinceBoink * 0.9 : 0 }

    var brightColor: NSColor { rainbowTurn == 0 ? jellyBright : shifted(jellyBright, by: rainbowTurn) }

    var deepColor: NSColor { rainbowTurn == 0 ? jellyDeep : shifted(jellyDeep, by: rainbowTurn) }

    var isCrowded: Bool { blobs.count > crowdedAt }

    var jellyPath: NSBezierPath { me.jelly.path(every: isCrowded ? 2 : 1) }

    func drawWhirlwind() {
        guard weapon == .axe else { return }
        let strength = clamp((abs(spin) - whirlSpin * 0.6) / (whirlSpin * 0.8), 0, 1)
        guard strength > 0 else { return }
        let turn = spin > 0 ? 1 : -1 as CGFloat
        for ring in 0..<4 {
            let r = whirlReach * (0.55 + 0.17 * CGFloat(ring))
            let start = (angle * 57.3 + CGFloat(ring) * 77) .truncatingRemainder(dividingBy: 360)
            let gust = NSBezierPath()
            gust.appendArc(withCenter: handle, radius: r, startAngle: start, endAngle: start - turn * 140, clockwise: turn > 0)
            gust.lineWidth = 3 + CGFloat(ring) * 1.5
            gust.lineCapStyle = .round
            NSColor(calibratedRed: 0.75, green: 0.9, blue: 1, alpha: 0.3 * strength * (1 - CGFloat(ring) * 0.15)).setStroke()
            gust.stroke()
        }
        if isWhirling {
            NSColor(calibratedRed: 0.75, green: 0.9, blue: 1, alpha: 0.08).setFill()
            circle(handle, whirlReach).fill()
            if Int(clock * 60) % 3 == 0 {
                let a = CGFloat.random(in: 0...(2 * .pi))
                particles.append(Particle(position: CGPoint(x: handle.x + cos(a) * whirlReach, y: max(ground, handle.y + sin(a) * whirlReach)),
                                          velocity: CGVector(dx: -sin(a) * 400 * turn, dy: cos(a) * 400 * turn + 120),
                                          life: 0, span: 0.5, size: CGFloat.random(in: 2...4), color: NSColor.white.withAlphaComponent(0.6)))
            }
        }
    }

    func drawSwoosh() {
        for (index, pair) in zip(swoosh, swoosh.dropFirst()).enumerated() {
            let fraction = CGFloat(index) / CGFloat(swooshLength)
            let streak = NSBezierPath()
            streak.move(to: pair.0)
            streak.line(to: pair.1)
            streak.lineWidth = weapon == .bat ? 1 + fraction * 7 : 1 + fraction * 3
            streak.lineCapStyle = .round
            let tint = weapon == .saber ? saberGlows[tier(.saber)] : NSColor.white
            streak.lineWidth = weapon == .saber ? 2 + fraction * 10 : streak.lineWidth
            tint.withAlphaComponent(fraction * fraction * [0.14, 0.4, 0.55, 0.14, 0.3][weapon.index]).setStroke()
            streak.stroke()
        }
    }

    func drawBat() {
        let dx = barrel.x - handle.x
        let dy = barrel.y - handle.y
        let length = max(hypot(dx, dy), 0.001)
        let along = CGVector(dx: dx / length, dy: dy / length)
        let side = CGVector(dx: -along.dy, dy: along.dx)
        func at(_ t: CGFloat, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: handle.x + along.dx * length * t + side.dx * offset, y: handle.y + along.dy * length * t + side.dy * offset)
        }
        func width(_ t: CGFloat) -> CGFloat {
            let s = clamp((t - 0.3) / 0.6, 0, 1)
            return 3 + 7 * s * s * (3 - 2 * s)
        }

        let samples = 24
        let bat = NSBezierPath()
        bat.move(to: at(0, width(0)))
        for i in 1...samples { let t = CGFloat(i) / CGFloat(samples); bat.line(to: at(t, width(t))) }
        bat.appendArc(withCenter: barrel, radius: width(1), startAngle: atan2(side.dy, side.dx) * 180 / .pi, endAngle: atan2(-side.dy, -side.dx) * 180 / .pi, clockwise: true)
        for i in stride(from: samples, through: 0, by: -1) { let t = CGFloat(i) / CGFloat(samples); bat.line(to: at(t, -width(t))) }
        bat.close()

        if held != nil {
            bat.lineWidth = 6
            NSColor.systemYellow.withAlphaComponent(0.5).setStroke()
            bat.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        bat.addClip()
        let isMetal = tier(.bat) == 1
        let (body, edge) = isMetal ? (steel, steelDark) : (wood, woodDark)
        NSGradient(colors: [edge, body, body.blended(withFraction: isMetal ? 0.7 : 0.4, of: .white) ?? body, body, edge])?
            .draw(from: at(0.5, -width(1)), to: at(0.5, width(1)), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        for band in stride(from: CGFloat(0.04), through: 0.26, by: 0.055) {
            let grip = NSBezierPath()
            grip.move(to: at(band, width(band) + 1))
            grip.line(to: at(band + 0.025, -width(band) - 1))
            grip.lineWidth = 5
            tape.setStroke()
            grip.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        bat.lineWidth = 1.2
        edge.setStroke()
        bat.stroke()

        if tier(.bat) == 2 {
            let nails = NSBezierPath()
            for (i, t) in stride(from: CGFloat(0.62), through: 0.96, by: 0.06).enumerated() {
                let side: CGFloat = i % 2 == 0 ? 1 : -1
                nails.move(to: at(t, side * (width(t) - 1)))
                nails.line(to: at(t + 0.015, side * (width(t) + 7)))
            }
            nails.lineWidth = 1.8
            nails.lineCapStyle = .round
            steelDark.setStroke()
            nails.stroke()
        }

        edge.setFill()
        circle(handle, 5.5).fill()
    }

    func drawAxe() {
        let dx = barrel.x - handle.x
        let dy = barrel.y - handle.y
        let length = max(hypot(dx, dy), 0.001)
        let along = CGVector(dx: dx / length, dy: dy / length)
        let side = CGVector(dx: -along.dy, dy: along.dx)
        func at(_ t: CGFloat, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: handle.x + along.dx * length * t + side.dx * offset, y: handle.y + along.dy * length * t + side.dy * offset)
        }

        let shaft = NSBezierPath()
        shaft.move(to: at(0, 0))
        shaft.line(to: at(0.97, 0))
        shaft.lineCapStyle = .round
        if held != nil {
            shaft.lineWidth = 11
            NSColor.systemYellow.withAlphaComponent(0.35).setStroke()
            shaft.stroke()
        }
        shaft.lineWidth = 6
        woodDark.setStroke()
        shaft.stroke()
        shaft.lineWidth = 3.5
        wood.setStroke()
        shaft.stroke()
        for band in [0.04, 0.1, 0.16] as [CGFloat] {
            let grip = NSBezierPath()
            grip.move(to: at(band, 3.5))
            grip.line(to: at(band + 0.03, -3.5))
            grip.lineWidth = 3
            NSColor(calibratedRed: 0.35, green: 0.2, blue: 0.1, alpha: 1).setStroke()
            grip.stroke()
        }

        let grade = tier(.axe)
        let reach: CGFloat = [0.85, 1, 1.18][grade]
        let gold = NSColor(calibratedRed: 0.98, green: 0.8, blue: 0.3, alpha: 1)
        let (metal, metalDark) = grade == 2 ? (gold, brass) : (steel, steelDark)
        for flank: CGFloat in grade == 0 ? [1] : [-1, 1] {
            let bit = NSBezierPath()
            bit.move(to: at(0.84, flank * 3))
            bit.line(to: at(0.74, flank * 27 * reach))
            bit.curve(to: at(1.06, flank * 27 * reach), controlPoint1: at(0.82, flank * 40 * reach), controlPoint2: at(1.0, flank * 40 * reach))
            bit.line(to: at(0.96, flank * 3))
            bit.close()
            NSGraphicsContext.saveGraphicsState()
            bit.addClip()
            NSGradient(colors: [metalDark, metal, .white, metal])?
                .draw(from: at(0.9, 0), to: at(0.9, flank * 36 * reach), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
            NSGraphicsContext.restoreGraphicsState()
            bit.lineWidth = 1
            metalDark.setStroke()
            bit.stroke()
            let edge = NSBezierPath()
            edge.move(to: at(0.75, flank * 25.5 * reach))
            edge.curve(to: at(1.05, flank * 25.5 * reach), controlPoint1: at(0.82, flank * 38 * reach), controlPoint2: at(1.0, flank * 38 * reach))
            edge.lineWidth = 1.4
            NSColor.white.withAlphaComponent(isWhirling ? 1 : 0.75).setStroke()
            edge.stroke()
        }
        steelDark.setFill()
        circle(at(0.9, 0), 4.5).fill()
        steel.setFill()
        circle(at(0.9, 0), 2.5).fill()
        woodDark.setFill()
        circle(handle, 4.5).fill()
    }

    func drawKatana() {
        let dx = barrel.x - handle.x
        let dy = barrel.y - handle.y
        let length = max(hypot(dx, dy), 0.001)
        let along = CGVector(dx: dx / length, dy: dy / length)
        let side = CGVector(dx: -along.dy, dy: along.dx)
        func at(_ t: CGFloat, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: handle.x + along.dx * length * t + side.dx * offset, y: handle.y + along.dy * length * t + side.dy * offset)
        }
        let guardAt: CGFloat = 0.25
        func curve(_ t: CGFloat) -> CGFloat { t <= guardAt ? 0 : 5 * sin(.pi * (t - guardAt) / (1 - guardAt)) }
        func width(_ t: CGFloat) -> CGFloat { t > 0.93 ? 4.4 * (1 - t) / 0.07 : 4.4 - 1.2 * (t - guardAt) }

        if held != nil {
            let glow = NSBezierPath()
            glow.move(to: at(0, 0))
            for i in 1...24 { let t = CGFloat(i) / 24; glow.line(to: at(t, curve(t))) }
            glow.lineWidth = 9
            glow.lineCapStyle = .round
            NSColor.systemYellow.withAlphaComponent(0.35).setStroke()
            glow.stroke()
        }

        let blade = NSBezierPath()
        let samples = 30
        blade.move(to: at(guardAt, curve(guardAt) + width(guardAt) / 2))
        for i in 1...samples {
            let t = guardAt + (1 - guardAt) * CGFloat(i) / CGFloat(samples)
            blade.line(to: at(t, curve(t) + width(t) / 2))
        }
        for i in stride(from: samples, through: 0, by: -1) {
            let t = guardAt + (1 - guardAt) * CGFloat(i) / CGFloat(samples)
            blade.line(to: at(t, curve(t) - width(t) / 2))
        }
        blade.close()
        if tier(.katana) == 2 {
            blade.lineWidth = 7 + sin(clock * 6) * 1.5
            NSColor(calibratedRed: 0.8, green: 0.05, blue: 0.15, alpha: 0.45).setStroke()
            blade.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        blade.addClip()
        NSGradient(colors: tier(.katana) == 2 ? [NSColor(calibratedWhite: 0.15, alpha: 1), steelDark, steel, steelDark] : [steelDark, steel, .white, steel])?
            .draw(from: at(0.6, 6), to: at(0.6, -4), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        let hamon = NSBezierPath()
        for i in 0...samples {
            let t = guardAt + (1 - guardAt) * CGFloat(i) / CGFloat(samples)
            let point = at(t, curve(t) - width(t) * 0.15 + sin(t * 60) * 0.6)
            if i == 0 { hamon.move(to: point) } else { hamon.line(to: point) }
        }
        hamon.lineWidth = tier(.katana) == 0 ? 0.8 : 1.3
        [NSColor.white.withAlphaComponent(0.7), NSColor.systemCyan.withAlphaComponent(0.9), NSColor.systemRed.withAlphaComponent(0.9)][tier(.katana)].setStroke()
        hamon.stroke()
        let glint = (clock * 0.7).truncatingRemainder(dividingBy: 1)
        NSColor.white.withAlphaComponent(0.9).setFill()
        circle(at(guardAt + (1 - guardAt) * glint, curve(guardAt + (1 - guardAt) * glint)), 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        blade.lineWidth = 0.8
        steelDark.setStroke()
        blade.stroke()

        let grip = NSBezierPath()
        grip.move(to: at(0, 0))
        grip.line(to: at(guardAt, 0))
        grip.lineWidth = 6.5
        grip.lineCapStyle = .round
        wrap.setStroke()
        grip.stroke()
        for band in stride(from: CGFloat(0.02), through: guardAt - 0.03, by: 0.035) {
            let cross = NSBezierPath()
            cross.move(to: at(band, 3))
            cross.line(to: at(band + 0.018, -3))
            cross.move(to: at(band, -3))
            cross.line(to: at(band + 0.018, 3))
            cross.lineWidth = 1
            NSColor.white.withAlphaComponent(0.55).setStroke()
            cross.stroke()
        }

        let tsuba = NSBezierPath()
        tsuba.move(to: at(guardAt, 9))
        tsuba.line(to: at(guardAt, -9))
        tsuba.lineWidth = 4
        tsuba.lineCapStyle = .round
        brass.setStroke()
        tsuba.stroke()
        brass.setFill()
        circle(handle, 3.5).fill()
    }

    func weaponFrame() -> (at: (CGFloat, CGFloat) -> CGPoint, along: CGVector, length: CGFloat) {
        let dx = barrel.x - handle.x
        let dy = barrel.y - handle.y
        let length = max(hypot(dx, dy), 0.001)
        let along = CGVector(dx: dx / length, dy: dy / length)
        let side = CGVector(dx: -along.dy, dy: along.dx)
        let start = handle
        return ({ t, offset in
            CGPoint(x: start.x + along.dx * length * t + side.dx * offset, y: start.y + along.dy * length * t + side.dy * offset)
        }, along, length)
    }

    func drawSaber() {
        let (at, _, _) = weaponFrame()
        let flicker = 1 + 0.08 * sin(clock * 47) + 0.05 * sin(clock * 83)
        let blade = NSBezierPath()
        blade.move(to: at(0.22, 0))
        blade.line(to: at(1, 0))
        blade.lineCapStyle = .round
        for (width, alpha) in [(18.0, 0.18), (11.0, 0.35), (6.0, 0.7)] as [(CGFloat, CGFloat)] {
            blade.lineWidth = width * flicker
            saberGlows[tier(.saber)].withAlphaComponent(alpha).setStroke()
            blade.stroke()
        }
        blade.lineWidth = 3
        NSColor.white.setStroke()
        blade.stroke()

        let hilt = NSBezierPath()
        hilt.move(to: at(0, 0))
        hilt.line(to: at(0.23, 0))
        hilt.lineWidth = 8
        hilt.lineCapStyle = .butt
        steel.setStroke()
        hilt.stroke()
        for band in stride(from: CGFloat(0.03), through: 0.15, by: 0.04) {
            let ridge = NSBezierPath()
            ridge.move(to: at(band, 4.5))
            ridge.line(to: at(band, -4.5))
            ridge.lineWidth = 2.5
            NSColor.black.withAlphaComponent(0.75).setStroke()
            ridge.stroke()
        }
        let emitter = NSBezierPath()
        emitter.move(to: at(0.2, 5.5))
        emitter.line(to: at(0.2, -5.5))
        emitter.lineWidth = 3
        steelDark.setStroke()
        emitter.stroke()
        NSColor.systemRed.setFill()
        circle(at(0.1, 4.5), 1.6).fill()
    }

    // Held by the tail, the fish's body flops back against the swing.
    func drawFish() {
        let (at, _, _) = weaponFrame()
        let kind = tier(.fish)
        let girth: CGFloat = [0.75, 1.25, 1.0][kind]
        let snout: CGFloat = kind == 2 ? 0.8 : 1
        let flop = clamp(-spin * 4, -26, 26) + sin(clock * 9) * 2
        func bend(_ t: CGFloat) -> CGFloat { flop * t * t }
        func width(_ t: CGFloat) -> CGFloat {
            if t < 0.14 { return 4 }
            return 4 + 12 * girth * sin(.pi * min(1, (t - 0.14) / (snout - 0.14)) * 0.92)
        }
        func head(_ f: CGFloat) -> CGFloat { 0.14 + (snout - 0.14) * f }
        let body = NSBezierPath()
        let samples = 26
        body.move(to: at(0.14, bend(0.14) + width(0.14)))
        for i in 1...samples { let t = head(CGFloat(i) / CGFloat(samples)); body.line(to: at(t, bend(t) + width(t))) }
        for i in stride(from: samples, through: 0, by: -1) { let t = head(CGFloat(i) / CGFloat(samples)); body.line(to: at(t, bend(t) - width(t))) }
        body.close()

        let fishTop = [NSColor(calibratedRed: 0.35, green: 0.5, blue: 0.68, alpha: 1),
                       NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.58, alpha: 1),
                       NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.5, alpha: 1)][kind]
        let fishBelly = [NSColor(calibratedRed: 0.86, green: 0.9, blue: 0.96, alpha: 1),
                         NSColor(calibratedRed: 1, green: 0.62, blue: 0.5, alpha: 1),
                         NSColor(calibratedRed: 0.72, green: 0.78, blue: 0.9, alpha: 1)][kind]
        let fishLine = fishTop.blended(withFraction: 0.5, of: .black) ?? fishTop

        if kind == 2 {
            let bill = NSBezierPath()
            bill.move(to: at(snout - 0.04, bend(snout - 0.04) + 5.5))
            bill.line(to: at(1.04, bend(1.04)))
            bill.line(to: at(snout - 0.04, bend(snout - 0.04) - 3))
            bill.close()
            NSColor(calibratedRed: 0.3, green: 0.32, blue: 0.4, alpha: 1).setFill()
            bill.fill()
        }

        let tail = NSBezierPath()
        let spread = 13 * (kind == 2 ? 1.5 : girth)
        tail.move(to: at(0.16, bend(0.16)))
        tail.line(to: at(-0.02, bend(0) + spread))
        tail.line(to: at(0.04, bend(0.04)))
        tail.line(to: at(-0.02, bend(0) - spread))
        tail.close()
        fishTop.setFill()
        tail.fill()

        if held != nil {
            body.lineWidth = 6
            NSColor.systemYellow.withAlphaComponent(0.35).setStroke()
            body.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSGradient(starting: fishTop, ending: fishBelly)?.draw(from: at(0.6, bend(0.6) + 16 * girth), to: at(0.6, bend(0.6) - 16 * girth), options: [])
        for t in stride(from: CGFloat(0.3), through: snout - 0.2, by: 0.08) {
            let scale = NSBezierPath()
            scale.appendArc(withCenter: at(t, bend(t)), radius: 7 * girth, startAngle: 0, endAngle: 360)
            scale.lineWidth = 0.8
            NSColor.white.withAlphaComponent(0.25).setStroke()
            scale.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        body.lineWidth = 1.2
        fishLine.setStroke()
        body.stroke()

        let fin = NSBezierPath()
        let crest: CGFloat = kind == 2 ? 20 : 9
        fin.move(to: at(head(0.36), bend(head(0.36)) + width(head(0.36)) - 1))
        fin.line(to: at(head(0.45), bend(head(0.45)) + width(head(0.45)) + crest))
        fin.line(to: at(head(0.63), bend(head(0.63)) + width(head(0.63)) - 1))
        fin.close()
        fishTop.setFill()
        fin.fill()

        let eye = at(head(0.86), bend(head(0.86)) + 4 * girth)
        NSColor.white.setFill()
        circle(eye, 4.2).fill()
        NSColor.black.setFill()
        circle(eye, 2.2).fill()
        guard kind != 2 else { return }
        let mouth = NSBezierPath()
        mouth.move(to: at(head(0.965), bend(head(0.965)) - 1))
        mouth.line(to: at(head(0.92), bend(head(0.92)) - 4 * girth))
        mouth.lineWidth = 1.5
        fishLine.setStroke()
        mouth.stroke()
    }

    func drawJellyFlash() {
        let t = sinceBoink
        guard t < 0.3 else { return }
        let fade = 1 - t / 0.3
        let center = CGPoint(x: me.jellyX, y: bodyCenter.y + 10 * me.size)
        if t < 0.12 {
            withJellyTransform {
                NSColor.white.withAlphaComponent(0.75 * (1 - t / 0.12)).setFill()
                jellyPath.fill()
            }
        }
        let lines = NSBezierPath()
        for i in 0..<14 {
            let a = CGFloat(i) / 14 * 2 * .pi + 0.2
            let inner = (80 + t * 120) * me.size
            lines.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner * 0.7))
            lines.line(to: CGPoint(x: center.x + cos(a) * (inner + 30 * fade), y: center.y + sin(a) * (inner + 30 * fade) * 0.7))
        }
        lines.lineWidth = 2.5
        lines.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.7 * fade).setStroke()
        lines.stroke()
    }

    func drawBursts() {
        for burst in bursts {
            let t = age(burst.born)
            if burst.isRing {
                let fade = clamp(1 - t / 0.4, 0, 1)
                let radius = 40 + 260 * t * burst.size
                let ring = NSBezierPath(ovalIn: NSRect(x: burst.point.x - radius, y: burst.point.y - radius * 0.55, width: radius * 2, height: radius * 1.1))
                ring.lineWidth = 5 * fade
                NSColor.white.withAlphaComponent(0.55 * fade).setStroke()
                ring.stroke()
                continue
            }
            let grow = min(1, t / 0.05)
            let fade = clamp(1 - (t - 0.12) / 0.2, 0, 1)
            let size = burst.size * (0.5 + 0.7 * grow)
            let star = NSBezierPath()
            for i in 0..<24 {
                let a = CGFloat(i) / 24 * 2 * .pi + burst.born
                let r = i % 2 == 0 ? size : size * 0.45
                let point = CGPoint(x: burst.point.x + cos(a) * r, y: burst.point.y + sin(a) * r)
                if i == 0 { star.move(to: point) } else { star.line(to: point) }
            }
            star.close()
            burst.color.withAlphaComponent(0.95 * fade).setFill()
            star.fill()
            star.lineWidth = 2.5
            NSColor.white.withAlphaComponent(fade).setStroke()
            star.stroke()
            NSColor.white.withAlphaComponent(fade).setFill()
            circle(burst.point, size * 0.3).fill()
        }
    }

    func drawPenguin() {
        let facing = penguinFacing
        let body = penguinCenter
        let feet = handleAt.y - penguinReach + 2
        let walking = !isPenguinAirborne && abs(handleVelocity.dx) > 30
        let step = walking ? sin(clock * 16) : 0

        NSColor.black.withAlphaComponent(isPenguinAirborne ? 0.12 : 0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: body.x - 18, y: ground - 5, width: 36, height: 9)).fill()

        let orange = NSColor(calibratedRed: 1, green: 0.62, blue: 0.15, alpha: 1)
        orange.setFill()
        for side: CGFloat in [-1, 1] {
            let hop = isPenguinAirborne ? -4 + sin(clock * 9 + side) * 2 : max(0, step * side) * 5
            NSBezierPath(ovalIn: NSRect(x: body.x + side * 8 - 7, y: feet - 3 + hop, width: 14, height: 6)).fill()
        }

        NSGraphicsContext.saveGraphicsState()
        let waddle = NSAffineTransform()
        waddle.translateX(by: body.x, yBy: feet)
        waddle.rotate(byDegrees: walking ? step * 7 : 0)
        waddle.translateX(by: -body.x, yBy: -feet)
        waddle.concat()

        let shell = NSBezierPath(ovalIn: NSRect(x: body.x - 19, y: body.y - 24, width: 38, height: 48))
        NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.2, alpha: 1).setFill()
        shell.fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: body.x - 13 + facing * 2, y: body.y - 21, width: 26, height: 34)).fill()
        if isSlimed {
            NSColor.systemGreen.withAlphaComponent(0.45).setFill()
            shell.fill()
        }

        let face = CGPoint(x: body.x + facing * 3, y: body.y + 9)
        NSColor.white.setFill()
        for side: CGFloat in [-1, 1] { circle(CGPoint(x: face.x + side * 6.5, y: face.y + 1), 8).fill() }
        let tuft = NSBezierPath()
        for lean: CGFloat in [-3, 0, 3] {
            tuft.move(to: CGPoint(x: body.x + lean, y: body.y + 23))
            tuft.curve(to: CGPoint(x: body.x + lean * 1.8 + facing * 2, y: body.y + 30), controlPoint1: CGPoint(x: body.x + lean, y: body.y + 27), controlPoint2: CGPoint(x: body.x + lean * 1.5, y: body.y + 29))
        }
        tuft.lineWidth = 1.6
        tuft.lineCapStyle = .round
        NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.2, alpha: 1).setStroke()
        tuft.stroke()

        let isHurt = age(penguinHurtAt) < 1.6
        let isCheering = age(penguinCheerAt) < 0.6 && !isHurt
        for side: CGFloat in [-1, 1] {
            let eye = CGPoint(x: face.x + side * 6.5, y: face.y + 1)
            if isHurt {
                let swirl = NSBezierPath()
                for i in 0..<16 {
                    let t = CGFloat(i) / 15
                    let a = clock * 10 * side + t * 3 * .pi
                    let point = CGPoint(x: eye.x + cos(a) * 3.5 * t, y: eye.y + sin(a) * 3.5 * t)
                    if i == 0 { swirl.move(to: point) } else { swirl.line(to: point) }
                }
                swirl.lineWidth = 1.4
                NSColor.black.setStroke()
                swirl.stroke()
            } else if isCheering {
                let happy = NSBezierPath()
                happy.appendArc(withCenter: CGPoint(x: eye.x, y: eye.y - 1.5), radius: 3.5, startAngle: 20, endAngle: 160)
                happy.lineWidth = 2
                NSColor.black.setStroke()
                happy.stroke()
            } else {
                let scared = isAnyEnraged
                NSColor.black.setFill()
                let look = CGPoint(x: eye.x + facing * 0.8, y: eye.y)
                circle(look, scared ? 2.6 : 4).fill()
                NSColor.white.setFill()
                circle(CGPoint(x: look.x + 1.3, y: look.y + 1.5), scared ? 0.9 : 1.5).fill()
                circle(CGPoint(x: look.x - 1.2, y: look.y - 1.4), 0.6).fill()
            }
        }

        let beak = NSBezierPath()
        beak.move(to: CGPoint(x: face.x - 3 + facing * 2, y: face.y - 5))
        beak.line(to: CGPoint(x: face.x + facing * 6, y: face.y - 7))
        beak.line(to: CGPoint(x: face.x + 3 + facing * 2, y: face.y - 9))
        beak.close()
        orange.setFill()
        beak.fill()

        if isAnyEnraged && !isHurt {
            let drip = (clock * 30).truncatingRemainder(dividingBy: 14)
            NSColor.systemCyan.withAlphaComponent(0.8 * (1 - drip / 14)).setFill()
            circle(CGPoint(x: body.x - facing * 16, y: body.y + 14 - drip), 2.5).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if isHurt {
            for i in 0..<3 {
                let a = clock * 6 + CGFloat(i) * 2 * .pi / 3
                drawText("★", at: CGPoint(x: body.x + cos(a) * 18, y: body.y + 22 + sin(a) * 4), size: 10, color: .systemYellow, weight: .regular)
            }
        }
    }

    func drawFlippers() {
        let body = penguinCenter
        for side: CGFloat in [-1, 1] {
            let shoulder = CGPoint(x: body.x + side * 15, y: body.y + 4)
            let grip = CGPoint(x: handleAt.x + side * 3, y: handleAt.y)
            let flipper = NSBezierPath()
            flipper.move(to: shoulder)
            flipper.curve(to: grip, controlPoint1: CGPoint(x: shoulder.x + side * 6, y: shoulder.y + 12), controlPoint2: CGPoint(x: grip.x + side * 8, y: grip.y - 6))
            flipper.lineWidth = 6.5
            flipper.lineCapStyle = .round
            NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.2, alpha: 1).setStroke()
            flipper.stroke()
        }
    }

    func drawJellyShadow(_ blob: NSBezierPath) {
        let width = (blob.bounds.width - 12) * me.size
        let height = clamp(me.lift / 300, 0, 0.7)
        let shadow = width * (1 - height)
        NSColor.black.withAlphaComponent(0.25 * (1 - height)).setFill()
        NSBezierPath(ovalIn: NSRect(x: me.jellyX - shadow / 2, y: ground - 7, width: shadow, height: 12)).fill()
    }

    func drawJellyBody(_ blob: NSBezierPath) {
        let box = blob.bounds
        NSGraphicsContext.saveGraphicsState()
        blob.addClip()
        if rainbowTurn == 0, let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .low
            context.draw(jellyTexture, in: box)
        } else {
            paintJellyGradients(in: box, bright: brightColor, deep: deepColor)
        }
        drawRage(in: box)

        for bubble in isCrowded ? [] : bubbles {
            let rise = (clock * bubble.speed / box.height + bubble.phase).truncatingRemainder(dividingBy: 1)
            let ring = circle(CGPoint(x: box.midX + bubble.x * box.width * 0.45, y: box.minY + rise * box.height), bubble.size)
            NSColor.white.withAlphaComponent(0.18 * (1 - rise)).setFill()
            ring.fill()
            ring.lineWidth = 0.8
            NSColor.white.withAlphaComponent(0.5 * (1 - rise)).setStroke()
            ring.stroke()
        }
        drawJellyShine(in: box)
        NSGraphicsContext.restoreGraphicsState()

        blob.lineWidth = 2.5
        (jellyRim.blended(withFraction: shownRage * 0.9, of: NSColor(calibratedRed: 0.45, green: 0, blue: 0.05, alpha: 1)) ?? jellyRim).setStroke()
        blob.stroke()
    }

    // Rage fills the jelly like a rising red tide, its surface sloshing.
    func drawRage(in box: NSRect) {
        guard shownRage > 0.01 else { return }
        let level = box.minY + (box.height + 8) * shownRage
        let tide = NSBezierPath()
        tide.move(to: CGPoint(x: box.minX - 4, y: box.minY - 4))
        for i in 0...40 {
            let x = box.minX - 4 + (box.width + 8) * CGFloat(i) / 40
            tide.line(to: CGPoint(x: x, y: level + sin(x * 0.12 + clock * 5) * 3 + sin(x * 0.05 - clock * 3) * 2))
        }
        tide.line(to: CGPoint(x: box.maxX + 4, y: box.minY - 4))
        tide.close()
        let evil = NSColor(calibratedRed: 1, green: 0.22, blue: 0.16, alpha: 0.95)
        let ember = NSColor(calibratedRed: 0.62, green: 0.02, blue: 0.08, alpha: 0.97)
        NSGraphicsContext.saveGraphicsState()
        tide.addClip()
        NSGradient(starting: ember, ending: evil)?.draw(in: NSRect(x: box.minX, y: box.minY, width: box.width, height: max(level - box.minY, 1)), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        tide.lineWidth = 1.5
        NSColor(calibratedRed: 1, green: 0.55, blue: 0.4, alpha: 0.6).setStroke()
        tide.stroke()
    }

    func drawJellyShine(in box: NSRect) {
        let shine = NSBezierPath()
        shine.appendArc(withCenter: CGPoint(x: box.midX, y: box.minY + box.height * 0.2), radius: box.width * 0.42, startAngle: 120, endAngle: 150)
        shine.lineWidth = 7
        shine.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.6).setStroke()
        shine.stroke()
        NSColor.white.withAlphaComponent(0.85).setFill()
        circle(CGPoint(x: box.minX + box.width * 0.17, y: box.minY + box.height * 0.42), 3).fill()
        NSColor.white.withAlphaComponent(0.5).setFill()
        circle(CGPoint(x: box.maxX - box.width * 0.13, y: box.minY + box.height * 0.3), 2).fill()
    }

    var faceTop: CGFloat { min(me.jelly.peak, jellyCenter.y + blobTop * 1.2) }

    func eye(_ side: CGFloat) -> CGPoint { CGPoint(x: me.jellyX + side * 16, y: faceTop - 20) }

    var mouth: CGPoint { CGPoint(x: me.jellyX, y: faceTop - 36) }

    func drawFace() {
        if isKO {
            drawKnockedOutFace()
        } else if isEnraged {
            drawEnragedFace()
        } else if isStunned || isDizzy {
            drawDizzyFace()
        } else if isRelieved {
            drawRelievedFace()
        } else if me.isScared || isSore || isDashing {
            drawScaredFace()
        } else {
            drawCalmFace()
        }
    }

    func drawEyes(radius: CGFloat, pupil: CGFloat) {
        for side: CGFloat in [-1, 1] {
            let center = eye(side)
            NSColor.white.setFill()
            circle(center, radius).fill()
            let gaze = CGVector(dx: barrel.x - center.x, dy: barrel.y - center.y)
            let length = max(hypot(gaze.dx, gaze.dy), 0.001)
            let reach = radius - pupil - 0.5
            NSColor.black.setFill()
            circle(CGPoint(x: center.x + gaze.dx / length * reach, y: center.y + gaze.dy / length * reach), pupil).fill()
        }
    }

    func drawAngryBrows() {
        guard me.rage > 0.5 else { return }
        let tilt = 3 + 5 * (me.rage - 0.5) / 0.5
        for side: CGFloat in [-1, 1] {
            let center = eye(side)
            let brow = NSBezierPath()
            brow.move(to: CGPoint(x: center.x - side * 1, y: center.y + 8))
            brow.line(to: CGPoint(x: center.x + side * 10, y: center.y + 8 + tilt))
            brow.lineWidth = 3
            brow.lineCapStyle = .round
            ink.setStroke()
            brow.stroke()
        }
    }

    func drawSteam() {
        guard me.rage > 0.8 || isEnraged else { return }
        for i in 0..<4 {
            let phase = (clock * 0.9 + CGFloat(i) * 0.25).truncatingRemainder(dividingBy: 1)
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            let puff = CGPoint(x: me.jellyX + side * (30 + phase * 18), y: faceTop + 6 + phase * 40)
            NSColor.white.withAlphaComponent(0.5 * (1 - phase)).setFill()
            circle(puff, 5 + phase * 9).fill()
        }
    }

    func drawEnragedFace() {
        for side: CGFloat in [-1, 1] {
            let center = eye(side)
            NSColor(calibratedRed: 1, green: 0.2, blue: 0.1, alpha: 0.35).setFill()
            circle(center, 12 + sin(clock * 20) * 1.5).fill()
            NSColor(calibratedRed: 1, green: 0.95, blue: 0.6, alpha: 1).setFill()
            circle(center, 6.5).fill()
            NSColor.systemRed.setFill()
            circle(center, 3.2).fill()
            let brow = NSBezierPath()
            brow.move(to: CGPoint(x: center.x - side * 2, y: center.y + 6))
            brow.line(to: CGPoint(x: center.x + side * 11, y: center.y + 16))
            brow.lineWidth = 4
            brow.lineCapStyle = .round
            ink.setStroke()
            brow.stroke()
        }
        let grin = NSBezierPath()
        grin.move(to: CGPoint(x: mouth.x - 18, y: mouth.y + 4))
        grin.curve(to: CGPoint(x: mouth.x + 18, y: mouth.y + 4), controlPoint1: CGPoint(x: mouth.x - 8, y: mouth.y - 12), controlPoint2: CGPoint(x: mouth.x + 8, y: mouth.y - 12))
        grin.close()
        NSColor(calibratedRed: 0.2, green: 0, blue: 0, alpha: 0.9).setFill()
        grin.fill()
        let teeth = NSBezierPath()
        for i in 0...6 {
            let x = mouth.x - 15 + CGFloat(i) * 5
            let point = CGPoint(x: x, y: i % 2 == 0 ? mouth.y + 2 : mouth.y - 4)
            if i == 0 { teeth.move(to: point) } else { teeth.line(to: point) }
        }
        teeth.lineWidth = 2
        NSColor.white.setStroke()
        teeth.stroke()
        drawSteam()
    }

    func drawCalmFace() {
        drawEyes(radius: 7, pupil: 3.5)
        drawAngryBrows()
        drawSteam()
        let smile = NSBezierPath()
        smile.appendArc(withCenter: CGPoint(x: mouth.x, y: mouth.y + 6), radius: 14, startAngle: 200, endAngle: 340)
        smile.lineWidth = 2.5
        smile.lineCapStyle = .round
        ink.setStroke()
        smile.stroke()
    }

    func drawScaredFace() {
        drawEyes(radius: 8.5, pupil: 2.3)
        if me.rage > 0.5 {
            drawAngryBrows()
            drawSteam()
        }
        for side: CGFloat in me.rage > 0.5 ? [] : [-1, 1] {
            let center = eye(side)
            let brow = NSBezierPath()
            brow.move(to: CGPoint(x: center.x - side * 2, y: center.y + 15))
            brow.line(to: CGPoint(x: center.x + side * 9, y: center.y + 10))
            brow.lineWidth = 2
            brow.lineCapStyle = .round
            ink.setStroke()
            brow.stroke()
        }

        let tremble = sin(clock * 50) * (isCornered ? 1.5 : 0.6)
        ink.setFill()
        NSBezierPath(ovalIn: NSRect(x: mouth.x - 6 + tremble, y: mouth.y - 7, width: 12, height: 13)).fill()

        let drip = (clock * 40).truncatingRemainder(dividingBy: 30)
        NSColor.systemCyan.withAlphaComponent(0.85 * (1 - drip / 30)).setFill()
        for side: CGFloat in [-1, 1] {
            let sweat = CGPoint(x: me.jellyX + side * 44, y: faceTop - 14 - drip)
            let drop = NSBezierPath()
            drop.move(to: CGPoint(x: sweat.x, y: sweat.y + 6))
            drop.curve(to: CGPoint(x: sweat.x, y: sweat.y - 4), controlPoint1: CGPoint(x: sweat.x + 5, y: sweat.y - 2), controlPoint2: CGPoint(x: sweat.x + 4, y: sweat.y - 4))
            drop.curve(to: CGPoint(x: sweat.x, y: sweat.y + 6), controlPoint1: CGPoint(x: sweat.x - 4, y: sweat.y - 4), controlPoint2: CGPoint(x: sweat.x - 5, y: sweat.y - 2))
            drop.fill()
        }

        if isSore {
            for side: CGFloat in [-1, 1] {
                let fall = (clock * 25 + (side > 0 ? 18 : 0)).truncatingRemainder(dividingBy: 36)
                NSColor.systemBlue.withAlphaComponent(0.85 * (1 - fall / 36)).setFill()
                NSBezierPath(ovalIn: NSRect(x: eye(side).x + side * 5 - 2.5, y: eye(side).y - 12 - fall, width: 5, height: 7)).fill()
            }
        }
    }

    func drawRelievedFace() {
        for side: CGFloat in [-1, 1] {
            let lid = NSBezierPath()
            lid.appendArc(withCenter: eye(side), radius: 6, startAngle: 20, endAngle: 160)
            lid.lineWidth = 2.5
            lid.lineCapStyle = .round
            ink.setStroke()
            lid.stroke()
        }
        let smile = NSBezierPath()
        smile.appendArc(withCenter: CGPoint(x: mouth.x, y: mouth.y + 8), radius: 12, startAngle: 210, endAngle: 330)
        smile.lineWidth = 2.5
        smile.lineCapStyle = .round
        smile.stroke()
    }

    func drawDizzyFace() {
        let spin = clock * 8
        let googly: CGFloat = isWeird(.googly) ? 1.9 + 0.25 * sin(clock * 14) : (sinceBoink < 0.35 ? 1.8 - sinceBoink * 2.3 : 1)
        for side: CGFloat in [-1, 1] {
            let center = CGPoint(x: me.jellyX + side * 16 * (googly > 1 ? 1.25 : 1), y: faceTop - 20)
            NSColor.white.setFill()
            circle(center, 7 * googly).fill()
            let spiral = NSBezierPath()
            for i in 0..<30 {
                let t = CGFloat(i) / 29
                let angle = spin * side + t * 3 * .pi
                let point = CGPoint(x: center.x + cos(angle) * 6 * googly * t, y: center.y + sin(angle) * 6 * googly * t)
                if i == 0 { spiral.move(to: point) } else { spiral.line(to: point) }
            }
            spiral.lineWidth = 1.5
            NSColor.black.setStroke()
            spiral.stroke()
        }

        let wobble = NSBezierPath()
        for i in 0..<25 {
            let t = CGFloat(i) / 24
            let point = CGPoint(x: mouth.x - 12 + t * 24, y: mouth.y + sin(t * 4 * .pi + spin) * 3)
            if i == 0 { wobble.move(to: point) } else { wobble.line(to: point) }
        }
        wobble.lineWidth = 2.5
        wobble.lineCapStyle = .round
        ink.setStroke()
        wobble.stroke()

        let stars = 3 + Int(me.boinkPower.rounded()) * 2
        for i in 0..<stars {
            let angle = clock * (4 + me.boinkPower) + CGFloat(i) * 2 * .pi / CGFloat(stars)
            drawStar(at: CGPoint(x: me.jellyX + cos(angle) * 34, y: faceTop + 10 + sin(angle) * 8))
        }
    }

    func drawKnockedOutFace() {
        for side: CGFloat in [-1, 1] {
            let center = eye(side)
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: center.x - 6, y: center.y - 6))
            cross.line(to: CGPoint(x: center.x + 6, y: center.y + 6))
            cross.move(to: CGPoint(x: center.x - 6, y: center.y + 6))
            cross.line(to: CGPoint(x: center.x + 6, y: center.y - 6))
            cross.lineWidth = 3
            cross.lineCapStyle = .round
            ink.setStroke()
            cross.stroke()
        }
        let tongue = NSBezierPath(ovalIn: NSRect(x: mouth.x + 2, y: mouth.y - 12, width: 9, height: 12))
        NSColor.systemPink.setFill()
        tongue.fill()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: mouth.x - 12, y: mouth.y))
        line.line(to: CGPoint(x: mouth.x + 12, y: mouth.y))
        line.lineWidth = 2.5
        line.lineCapStyle = .round
        ink.setStroke()
        line.stroke()
    }

    func drawParticles() {
        for particle in particles {
            let fade = 1 - particle.life / particle.span
            particle.color.withAlphaComponent(0.9 * fade).setFill()
            circle(particle.position, particle.size * (0.6 + 0.4 * fade)).fill()
        }
    }

    func drawRageMeter() {
        guard me.rage > 0.01 || isEnraged else { return }
        let width: CGFloat = 84
        let frame = NSRect(x: me.jellyX - width / 2, y: jellyTop + 24, width: width, height: 5)
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4).fill()
        let pulse = me.rage >= 1 || isEnraged ? 0.6 + 0.4 * abs(sin(clock * 12)) : 1
        NSColor.systemRed.withAlphaComponent(pulse).setFill()
        NSBezierPath(roundedRect: NSRect(x: frame.minX, y: frame.minY, width: frame.width * (isEnraged ? 1 : me.rage), height: frame.height), xRadius: 3, yRadius: 3).fill()
        rageIcon.draw(at: CGPoint(x: frame.minX - 12 - rageIcon.size.width / 2, y: frame.minY - 7), from: .zero, operation: .sourceOver, fraction: 1)
    }

    func drawSpit() {
        guard let blob = me.slime else { return }
        NSColor.systemGreen.withAlphaComponent(0.9).setFill()
        circle(blob.position, 9).fill()
        NSColor.white.withAlphaComponent(0.6).setFill()
        circle(CGPoint(x: blob.position.x - 3, y: blob.position.y + 3), 2.5).fill()
    }

    func drawSlimedBat() {
        guard isSlimed else { return }
        let fade = clamp((slimeFor - age(slimedAt)) / 0.6, 0, 1)
        let goo = NSBezierPath()
        goo.move(to: handle)
        goo.line(to: barrel)
        goo.lineWidth = 12
        goo.lineCapStyle = .round
        NSColor.systemGreen.withAlphaComponent(0.55 * fade).setStroke()
        goo.stroke()
        for i in 0..<5 {
            let along = (CGFloat(i) + 0.5) / 5
            let drip = (clock * 0.8 + CGFloat(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let spot = CGPoint(x: handle.x + (barrel.x - handle.x) * along, y: handle.y + (barrel.y - handle.y) * along - drip * 30)
            NSColor.systemGreen.withAlphaComponent(0.8 * fade * (1 - drip)).setFill()
            circle(spot, 3.5 - drip * 1.5).fill()
        }
    }

    func drawHealth() {
        drawRageMeter()
        guard me.health < me.maxHealth || isKO else { return }
        let width: CGFloat = 84
        let frame = NSRect(x: me.jellyX - width / 2, y: jellyTop + 12, width: width, height: 8)
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6).fill()
        let level = me.health / me.maxHealth
        let color = level > 0.6 ? NSColor.systemGreen : level > 0.3 ? NSColor.systemYellow : NSColor.systemRed
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: frame.minX, y: frame.minY, width: max(0, frame.width * level), height: frame.height), xRadius: 4, yRadius: 4).fill()

        if isKO {
            let halo = NSRect(x: me.jellyX - 22, y: ground + 34 + sin(clock * 3) * 4, width: 44, height: 10)
            let ring = NSBezierPath(ovalIn: halo)
            ring.lineWidth = 3
            NSColor.systemYellow.withAlphaComponent(0.9).setStroke()
            ring.stroke()
        }
    }

    func drawPopups() {
        for popup in popups {
            let age = CGFloat(age(popup.born))
            let rise = 50 * (1 - pow(1 - min(1, age / 1.1), 2))
            let pop = 1 + 0.5 * exp(-age * 14)
            drawText(popup.text, at: CGPoint(x: popup.position.x, y: popup.position.y + 14 + rise), size: popup.size * pop, color: popup.color.withAlphaComponent(1 - age / 1.1), within: bounds.width)
        }
    }

    func drawBanner() {
        let age = CGFloat(age(bannerAt))
        let span: CGFloat = bannerText == "K.O.!!" || bannerText == "JELLY SMASH!" ? 2.2 : 1.3
        guard age < span else { return }
        let pop = 1 + 0.8 * exp(-age * 10) * cos(age * 24)
        let fade = clamp((span - age) / 0.35, 0, 1)
        let size = (bannerText == "K.O.!!" ? 84 : 46) * pop
        let tilt = NSAffineTransform()
        let center = CGPoint(x: bounds.midX, y: bounds.maxY - 230)
        tilt.translateX(by: center.x, yBy: center.y)
        tilt.rotate(byDegrees: sin(age * 9) * 4 * exp(-age * 2))
        tilt.translateX(by: -center.x, yBy: -center.y)
        NSGraphicsContext.saveGraphicsState()
        tilt.concat()
        drawText(bannerText, at: CGPoint(x: center.x + 3, y: center.y - 3), size: size, color: NSColor.black.withAlphaComponent(0.4 * fade), within: bounds.width)
        drawText(bannerText, at: center, size: size, color: bannerColor.withAlphaComponent(fade), within: bounds.width)
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawVibe() {
        let seat = vibeSeat
        let shellColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.2, alpha: 1)
        let orange = NSColor(calibratedRed: 1, green: 0.62, blue: 0.15, alpha: 1)

        // The scene is drawn facing right, then mirrored so the penguin looks back at the screen from the right corner.
        NSGraphicsContext.saveGraphicsState()
        let mirror = NSAffineTransform()
        mirror.translateX(by: seat.x * 2, yBy: 0)
        mirror.scaleX(by: -1, yBy: 1)
        mirror.concat()

        let pose = (handleAt, angle)
        let lean: CGFloat = -0.3
        handleAt = CGPoint(x: seat.x - 34 - weapon.length * sin(lean), y: seat.y + weapon.length * cos(lean))
        angle = lean
        switch weapon {
        case .bat: drawBat()
        case .katana: drawKatana()
        case .saber: drawSaber()
        case .fish: drawFish()
        case .axe: drawAxe()
        }
        (handleAt, angle) = pose

        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: seat.x - 28, y: seat.y - 5, width: 62, height: 10)).fill()

        orange.setFill()
        for side: CGFloat in [0, 1] {
            NSBezierPath(ovalIn: NSRect(x: seat.x + 10 + side * 6, y: seat.y - 2 + side * 3, width: 18, height: 7)).fill()
        }

        let breath = sin(vibeClock * 1.6) * 0.8
        let body = CGPoint(x: seat.x, y: seat.y + 21)
        shellColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: body.x - 21, y: body.y - 21, width: 42, height: 42 + breath)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: body.x - 13, y: body.y - 18, width: 28, height: 30 + breath)).fill()

        let face = CGPoint(x: body.x + 4, y: body.y + 8 + breath)
        if blowsBubbles {
            drawBubbleBreak(body: body, face: face, shellColor: shellColor, orange: orange)
        } else {
            drawSmokeBreak(body: body, face: face, shellColor: shellColor, orange: orange)
        }
        NSGraphicsContext.restoreGraphicsState()

        let hint: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]
        let caption = "~ vibing · F3 ~" as NSString
        caption.draw(at: CGPoint(x: seat.x - caption.size(withAttributes: hint).width / 2, y: seat.y - 22), withAttributes: hint)
    }

    func drawSmokeBreak(body: CGPoint, face: CGPoint, shellColor: NSColor, orange: NSColor) {
        // A slow drag every few seconds: the ember flares and the eyes close for a moment.
        let drag = max(0, sin(vibeClock * 1.4)) > 0.92
        for side: CGFloat in [-1, 1] {
            let eye = CGPoint(x: face.x + side * 6.5, y: face.y + 1)
            NSColor.white.setFill()
            circle(eye, 8).fill()
            if drag {
                let shut = NSBezierPath()
                shut.appendArc(withCenter: CGPoint(x: eye.x, y: eye.y + 1.5), radius: 3.5, startAngle: 200, endAngle: 340)
                shut.lineWidth = 2
                NSColor.black.setStroke()
                shut.stroke()
            } else {
                NSColor.black.setFill()
                circle(CGPoint(x: eye.x + 1, y: eye.y - 1), 3.2).fill()
                shellColor.setFill()
                NSBezierPath(rect: NSRect(x: eye.x - 4.2, y: eye.y - 0.2, width: 8.4, height: 4.4)).fill()
            }
        }

        let beak = NSBezierPath()
        beak.move(to: CGPoint(x: face.x - 1, y: face.y - 5))
        beak.line(to: CGPoint(x: face.x + 8, y: face.y - 7))
        beak.line(to: CGPoint(x: face.x + 5, y: face.y - 9))
        beak.close()
        orange.setFill()
        beak.fill()

        let lip = CGPoint(x: face.x + 7, y: face.y - 7.5)
        let ember = CGPoint(x: lip.x + 15, y: lip.y + 3)
        let cigarette = NSBezierPath()
        cigarette.move(to: lip)
        cigarette.line(to: ember)
        cigarette.lineWidth = 3
        cigarette.lineCapStyle = .round
        NSColor(calibratedWhite: 0.96, alpha: 1).setStroke()
        cigarette.stroke()
        let filter = NSBezierPath()
        filter.move(to: lip)
        filter.line(to: CGPoint(x: lip.x + 4, y: lip.y + 0.8))
        filter.lineWidth = 3
        orange.withAlphaComponent(0.8).setStroke()
        filter.stroke()
        let glow = drag ? 1 : 0.55 + 0.15 * sin(vibeClock * 5)
        NSColor.systemOrange.withAlphaComponent(0.35 * glow).setFill()
        circle(ember, 4.5).fill()
        NSColor(calibratedRed: 1, green: 0.3 + 0.3 * glow, blue: 0.1, alpha: 1).setFill()
        circle(ember, 1.8).fill()

        let flipper = NSBezierPath()
        flipper.move(to: CGPoint(x: body.x + 12, y: body.y + 2))
        flipper.curve(to: CGPoint(x: lip.x + 6, y: lip.y - 2), controlPoint1: CGPoint(x: body.x + 26, y: body.y - 4), controlPoint2: CGPoint(x: lip.x + 8, y: lip.y - 10))
        flipper.lineWidth = 6
        flipper.lineCapStyle = .round
        shellColor.setStroke()
        flipper.stroke()

        for i in 0..<7 {
            let t = (vibeClock * 0.3 + CGFloat(i) / 7).truncatingRemainder(dividingBy: 1)
            let puff = CGPoint(x: ember.x + t * 30 + sin(t * 7 + CGFloat(i)) * 8, y: ember.y + 4 + t * 130)
            NSColor(calibratedWhite: 0.85, alpha: 0.35 * (1 - t)).setFill()
            circle(puff, 3 + t * 16).fill()
        }

    }

    func drawBubbleBreak(body: CGPoint, face: CGPoint, shellColor: NSColor, orange: NSColor) {
        for side: CGFloat in [-1, 1] {
            let eye = CGPoint(x: face.x + side * 6.5, y: face.y + 1)
            NSColor.white.setFill()
            circle(eye, 8).fill()
            let happy = NSBezierPath()
            happy.appendArc(withCenter: CGPoint(x: eye.x, y: eye.y - 1.5), radius: 3.5, startAngle: 20, endAngle: 160)
            happy.lineWidth = 2
            NSColor.black.setStroke()
            happy.stroke()
        }
        NSColor.systemPink.withAlphaComponent(0.35).setFill()
        circle(CGPoint(x: face.x + 12, y: face.y - 6), 3).fill()

        let beak = NSBezierPath()
        beak.move(to: CGPoint(x: face.x - 1, y: face.y - 5))
        beak.line(to: CGPoint(x: face.x + 8, y: face.y - 7))
        beak.line(to: CGPoint(x: face.x + 5, y: face.y - 9))
        beak.close()
        orange.setFill()
        beak.fill()

        // Each blow fills the wand film and then lets a bubble go.
        let blow = (vibeClock * 0.8).truncatingRemainder(dividingBy: 1)
        let ring = CGPoint(x: face.x + 20, y: face.y - 2 + sin(vibeClock * 2) * 1.5)
        let wand = NSBezierPath()
        wand.move(to: CGPoint(x: body.x + 18, y: body.y - 6))
        wand.line(to: CGPoint(x: ring.x - 2, y: ring.y - 7))
        wand.lineWidth = 2
        wand.lineCapStyle = .round
        NSColor.systemPink.setStroke()
        wand.stroke()
        NSColor(calibratedRed: 0.7, green: 0.9, blue: 1, alpha: 0.2 + 0.25 * blow).setFill()
        circle(ring, 7).fill()
        let loop = circle(ring, 7)
        loop.lineWidth = 2
        NSColor.systemPink.setStroke()
        loop.stroke()

        let flipper = NSBezierPath()
        flipper.move(to: CGPoint(x: body.x + 12, y: body.y + 2))
        flipper.curve(to: CGPoint(x: body.x + 19, y: body.y - 5), controlPoint1: CGPoint(x: body.x + 22, y: body.y + 2), controlPoint2: CGPoint(x: body.x + 20, y: body.y - 2))
        flipper.lineWidth = 6
        flipper.lineCapStyle = .round
        shellColor.setStroke()
        flipper.stroke()

        let count = 9
        for i in 0..<count {
            let phase = vibeClock * 0.16 + CGFloat(i) / CGFloat(count)
            let t = phase.truncatingRemainder(dividingBy: 1)
            let seed = CGFloat(i * 7) + floor(phase) * 13
            func chance(_ salt: CGFloat) -> CGFloat { abs(sin((seed + salt) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1) }
            let size = (5 + chance(1) * 10) * min(1, t * 8)
            let lifespan = 0.75 + 0.25 * chance(2)
            guard t < lifespan else { continue }
            let spot = CGPoint(x: ring.x + 8 + t * (60 + chance(3) * 120) + sin(t * 9 + seed) * 10,
                               y: ring.y + t * (150 + chance(4) * 120) + sin(t * 5 + seed) * 6)
            if lifespan - t < 0.04 {
                let pop = NSBezierPath()
                for k in 0..<6 {
                    let a = CGFloat(k) * .pi / 3
                    pop.move(to: CGPoint(x: spot.x + cos(a) * size * 0.8, y: spot.y + sin(a) * size * 0.8))
                    pop.line(to: CGPoint(x: spot.x + cos(a) * size * 1.3, y: spot.y + sin(a) * size * 1.3))
                }
                pop.lineWidth = 1.2
                NSColor.white.withAlphaComponent(0.6).setStroke()
                pop.stroke()
                continue
            }
            NSColor.white.withAlphaComponent(0.07).setFill()
            circle(spot, size).fill()
            let film = circle(spot, size)
            film.lineWidth = 1.3
            NSColor(calibratedHue: (chance(5) + t * 0.6).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 1, alpha: 0.7).setStroke()
            film.stroke()
            let shine = NSBezierPath()
            shine.appendArc(withCenter: spot, radius: size * 0.65, startAngle: 100, endAngle: 150)
            shine.lineWidth = 1.5
            shine.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.8).setStroke()
            shine.stroke()
        }
    }

    func drawShop() {
        guard isShopping else { return }
        let panel = shopFrame
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 18, yRadius: 18).fill()
        drawText("SHOP", at: CGPoint(x: panel.midX, y: panel.maxY - 50), size: 32, color: .systemYellow, within: bounds.width)
        drawText("🪙 \(goldText) gold · next up: level \(nextLevel)", at: CGPoint(x: panel.midX, y: panel.maxY - 76), size: 14, color: .white, weight: .bold, within: bounds.width)

        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        for (row, ware) in wares.enumerated() {
            let frame = wareFrame(row)
            let cost = price(ware)
            let canBuy = cost.map { $0 <= gold } ?? false
            NSColor.white.withAlphaComponent(canBuy ? 0.18 : 0.06).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9).fill()
            let name: String
            let note: String
            switch ware {
            case .weapon(let choice):
                name = "\(choice.icon) \(choice.tierNames[0]) · \(choice.blurb)"
                note = cost.map { "\($0) 🪙" } ?? "owned ✓"
            case .forge(let choice):
                let names = choice.tierNames
                name = cost == nil ? "\(choice.icon) \(names[tier(choice)]) · fully forged" : "\(choice.icon) \(names[tier(choice)]) → \(names[tier(choice) + 1]) · +10% damage"
                note = cost.map { "\($0) 🪙" } ?? "maxed ✓"
                for pip in 0..<names.count {
                    (pip <= tier(choice) ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.2)).setFill()
                    circle(CGPoint(x: frame.maxX - 150 + CGFloat(pip) * 13, y: frame.midY), 4).fill()
                }
            case .upgrade(let upgrade):
                name = upgrade.label
                note = cost.map { "\($0) 🪙" } ?? "maxed ✓"
                for pip in 0..<maxRank {
                    (pip < rank(upgrade) ? NSColor.systemYellow : NSColor.white.withAlphaComponent(0.2)).setFill()
                    circle(CGPoint(x: frame.maxX - 150 + CGFloat(pip) * 13, y: frame.midY), 4).fill()
                }
            }
            let shade = NSColor.white.withAlphaComponent(canBuy || cost == nil ? 0.95 : 0.45)
            (name as NSString).draw(at: CGPoint(x: frame.minX + 12, y: frame.minY + 7), withAttributes: [.font: font, .foregroundColor: shade])
            let noteStyle: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: canBuy ? NSColor.systemYellow : shade]
            (note as NSString).draw(at: CGPoint(x: frame.maxX - 12 - (note as NSString).size(withAttributes: noteStyle).width, y: frame.minY + 7), withAttributes: noteStyle)
        }

        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: nextFrame, xRadius: 18, yRadius: 18).fill()
        let next = (isDev ? "LEVEL \(nextLevel) ▶" : "NEXT LEVEL ▶") as NSString
        let nextStyle: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .black), .foregroundColor: NSColor.white]
        let size = next.size(withAttributes: nextStyle)
        next.draw(at: CGPoint(x: nextFrame.midX - size.width / 2, y: nextFrame.midY - size.height / 2), withAttributes: nextStyle)
        for pick in devSteps {
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: pick.frame, xRadius: 12, yRadius: 12).fill()
            let label = (pick.step < 0 ? "−\(-pick.step)" : "+\(pick.step)") as NSString
            let labelSize = label.size(withAttributes: nextStyle)
            label.draw(at: CGPoint(x: pick.frame.midX - labelSize.width / 2, y: pick.frame.midY - labelSize.height / 2), withAttributes: nextStyle)
        }
    }

    func drawCountdown() {
        guard isCountingDown else { return }
        let into = age(countdownAt).truncatingRemainder(dividingBy: 1)
        let pop = 1 + 0.6 * exp(-into * 8)
        let fade = clamp((1 - into) / 0.3, 0, 1)
        let center = CGPoint(x: bounds.midX, y: bounds.midY + 20)
        drawText("LEVEL \(upcoming)", at: CGPoint(x: center.x, y: center.y + 135), size: 30, color: .systemBlue, within: bounds.width)
        let colors: [NSColor] = [.systemGreen, .systemYellow, .systemOrange, .systemRed, .systemPink]
        let color = colors[max(0, min(colors.count - 1, countLeft - 1))]
        drawText("\(countLeft)", at: CGPoint(x: center.x + 4, y: center.y - 4), size: 120 * pop, color: NSColor.black.withAlphaComponent(0.35 * fade), within: bounds.width)
        drawText("\(countLeft)", at: center, size: 120 * pop, color: color.withAlphaComponent(fade), within: bounds.width)
    }

    func drawGameOver() {
        guard isGameOver, age(gameOverAt) > 1 else { return }
        let fade = clamp((age(gameOverAt) - 1) / 0.4, 0, 1)
        NSColor.black.withAlphaComponent(0.45 * fade).setFill()
        bounds.fill()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        drawText("GAME OVER", at: CGPoint(x: center.x, y: center.y + 30), size: 64, color: NSColor.systemRed.withAlphaComponent(fade), within: bounds.width)
        drawText("reached level \(level) · score \(score)", at: CGPoint(x: center.x, y: center.y - 20), size: 22, color: NSColor.white.withAlphaComponent(fade), within: bounds.width)
        drawText("click to play again", at: CGPoint(x: center.x, y: center.y - 56), size: 16, color: NSColor.white.withAlphaComponent(0.8 * fade), weight: .bold, within: bounds.width)
    }

    func drawCaptions() {
        let top = jellyTop

        let showFor: CGFloat = 0.8 + 0.3 * me.boinkPower
        if sinceBoink < showFor && combo < 2 && !isKO {
            let fade = sinceBoink / showFor
            let level = min(3, Int(me.boinkPower.rounded()))
            let words = lastHitWasSlice ? ["SLICE!", "SLIIICE!!", "SLIIIIIICE!!!", "MEGA SLICE!!!"]
                : hitWeapon == .fish ? ["SLAP!", "SLAAP!!", "SLAAAAP!!!", "MEGA SLAP!!!"]
                : hitWeapon == .axe ? ["CHOP!", "CHOOP!!", "CHOOOOP!!!", "MEGA CHOP!!!"]
                : ["BOINK!", "BOOINK!!", "BOOOOINK!!!", "MEGA BOINK!!!"]
            let colors: [NSColor] = [.systemOrange, .systemOrange, .systemRed, .systemPurple]
            let shake = level >= 2 ? sin(sinceBoink * 60) * 4 * (1 - fade) : 0
            let size = 22 + 9 * me.boinkPower + sinceBoink * 14
            drawText(words[level], at: CGPoint(x: me.jellyX + shake, y: top + 46 + sinceBoink * 30), size: size, color: colors[level].withAlphaComponent(1 - fade), within: bounds.width)
        }

        let sinceDodge = CGFloat(age(me.dodgedAt))
        if sinceDodge < 0.9 {
            drawText("phew!", at: CGPoint(x: me.jellyX, y: top + 18 + sinceDodge * 20), size: 18, color: NSColor.systemTeal.withAlphaComponent(1 - sinceDodge / 0.9), within: bounds.width)
        }

        let sinceScared = CGFloat(age(me.scaredAt))
        if me.isScared && sinceScared < 0.6 && !isRelieved {
            drawText("!", at: CGPoint(x: me.jellyX, y: top + 16 + sinceScared * 10), size: 26, color: NSColor.systemRed.withAlphaComponent(1 - sinceScared / 0.6))
        }
        if me.fury == .windup {
            let build = age(me.furyAt) / windupFor
            drawText("GRRR!", at: CGPoint(x: me.jellyX + sin(clock * 80) * 3, y: top + 30), size: 20 + 10 * build, color: .systemRed, within: bounds.width)
        }
        if me.fury == .leap {
            drawText("HYAAA!", at: CGPoint(x: me.jellyX, y: top + 30), size: 22, color: .systemRed, within: bounds.width)
        }
        if isDashing {
            drawText("eep!", at: CGPoint(x: me.jellyX, y: top + 18), size: 16, color: .systemYellow, within: bounds.width)
        }
    }

    func drawScore() {
        let panel = NSRect(x: 16, y: bounds.maxY - 84, width: 430, height: 70)
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14).fill()

        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .heavy),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .kern: 1.5,
        ]
        let big: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .black),
            .foregroundColor: NSColor.white,
        ]
        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        func number(_ value: Int) -> String { formatter.string(from: NSNumber(value: value)) ?? "\(value)" }

        ("SCORE" as NSString).draw(at: CGPoint(x: panel.minX + 14, y: panel.maxY - 20), withAttributes: label)
        (number(score) as NSString).draw(at: CGPoint(x: panel.minX + 12, y: panel.maxY - 52), withAttributes: big)
        ("BEST" as NSString).draw(at: CGPoint(x: panel.minX + 170, y: panel.maxY - 20), withAttributes: label)
        (number(best) as NSString).draw(at: CGPoint(x: panel.minX + 170, y: panel.maxY - 38), withAttributes: small)
        ("💥\(boinks)  ⚔️\(slices)  😅\(dodges)  💀\(kos)  🟢\(jellyHits)  x\(bestCombo)  🪙\(goldText)" as NSString).draw(at: CGPoint(x: panel.minX + 14, y: panel.minY + 6), withAttributes: small)

        ("LEVEL \(isCountingDown ? upcoming : level)" as NSString).draw(at: CGPoint(x: panel.minX + 320, y: panel.maxY - 20), withAttributes: label)
        let seconds = isCountingDown ? levelTime : blobs.isEmpty ? 0 : timeLeft
        let clockStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .black),
            .foregroundColor: seconds < 3 && !blobs.isEmpty ? NSColor.systemRed : NSColor.white,
        ]
        (String(format: "%.1f", seconds) as NSString).draw(at: CGPoint(x: panel.minX + 318, y: panel.maxY - 52), withAttributes: clockStyle)
        NSColor.white.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: NSRect(x: panel.minX + 320, y: panel.minY + 10, width: 96, height: 4), xRadius: 2, yRadius: 2).fill()
        (seconds < 3 ? NSColor.systemRed : NSColor.systemGreen).setFill()
        NSBezierPath(roundedRect: NSRect(x: panel.minX + 320, y: panel.minY + 10, width: 96 * seconds / levelTime, height: 4), xRadius: 2, yRadius: 2).fill()

        if isComboLive && combo >= 1 {
            let left = isAnyAirborne ? 1 : 1 - CGFloat(age(lastHitAt) / comboWindow)
            let comboStyle: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .black),
                .foregroundColor: combo >= 3 ? NSColor.systemPink : NSColor.systemOrange,
            ]
            ("x\(combo)" as NSString).draw(at: CGPoint(x: panel.minX + 236, y: panel.maxY - 42), withAttributes: comboStyle)
            NSColor.white.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: panel.minX + 170, y: panel.minY + 26, width: 116, height: 4), xRadius: 2, yRadius: 2).fill()
            (combo >= 3 ? NSColor.systemPink : NSColor.systemOrange).setFill()
            NSBezierPath(roundedRect: NSRect(x: panel.minX + 170, y: panel.minY + 26, width: 116 * left, height: 4), xRadius: 2, yRadius: 2).fill()
        }

        let toggle = toggleFrame
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: toggle, xRadius: 13, yRadius: 13).fill()
        let slot = toggle.width / CGFloat(Weapon.all.count)
        let chosen = NSRect(x: toggle.minX + 2 + slot * CGFloat(weapon.index), y: toggle.minY + 2, width: slot - 4, height: toggle.height - 4)
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: chosen, xRadius: 11, yRadius: 11).fill()
        let option: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        var locked = option
        locked[.foregroundColor] = NSColor.white.withAlphaComponent(0.35)
        for choice in Weapon.all {
            let isOwned = owned.contains(choice)
            let label = (isOwned ? choice.label : "🔒 \(choice.price)") as NSString
            let style = isOwned ? option : locked
            let width = label.size(withAttributes: style).width
            label.draw(at: CGPoint(x: toggle.minX + slot * (CGFloat(choice.index) + 0.5) - width / 2, y: toggle.minY + 5), withAttributes: style)
        }

        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: vibeFrame, xRadius: 13, yRadius: 13).fill()
        let vibe = (blowsBubbles ? "🫧 vibe" : "🚬 vibe") as NSString
        vibe.draw(at: CGPoint(x: vibeFrame.midX - vibe.size(withAttributes: option).width / 2, y: vibeFrame.minY + 5), withAttributes: option)

    }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var view: BoinkView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let origin = NSPoint(x: screenArea.minX + 10, y: screenArea.minY + 10)
        panel = NSPanel(
            contentRect: NSRect(origin: origin, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        view = BoinkView(frame: NSRect(origin: .zero, size: windowSize))
        panel.contentView = view
        view.countIn(to: isDev ? argument(after: "--dev").flatMap { Int($0) }.map { max(1, $0) } ?? 1 : 1)
        panel.orderFrontRegardless()

        Timer.scheduledTimer(withTimeInterval: Double(tick), repeats: true) { [weak self] _ in self?.frame() }
        registerPauseKey()
    }

    // A Carbon hotkey fires even while another app has focus, and needs no accessibility permission.
    func registerPauseKey() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, delegate in
            Unmanaged<AppDelegate>.fromOpaque(delegate!).takeUnretainedValue().view.toggleVibe()
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
        var hotKey: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_F3), 0, EventHotKeyID(signature: OSType(0x626F696E), id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }

    // The window is transparent; clicks fall through to the terminal unless the pointer is on the bat.
    func frame() {
        let point = view.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if view.isVibing {
            view.vibeClock += tick
            view.needsDisplay = true
            panel.ignoresMouseEvents = !view.isOverVibingPenguin(point)
            return
        }
        view.step()
        panel.ignoresMouseEvents = !(view.canRestart || (view.isShopping && view.shopFrame.contains(point)) || view.held != nil || view.grip(at: point) != nil || view.isOverToggle(point))
    }
}

// Most trials were tuned with the bat in hand, so they start from it rather than the katana.
func batView() -> BoinkView {
    let view = BoinkView(frame: NSRect(origin: .zero, size: windowSize))
    view.weapon = .bat
    return view
}

func crossings(_ points: [CGPoint]) -> Int {
    func crosses(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
    }
    var count = 0
    for i in 0..<points.count {
        for j in min(i + 2, points.count)..<points.count where !(i == 0 && j == points.count - 1) {
            if crosses(points[i], points[(i + 1) % points.count], points[j], points[(j + 1) % points.count]) { count += 1 }
        }
    }
    return count
}

func save(_ view: NSView, to path: String) {
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func argument(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

if let path = argument(after: "--snapshot") {
    let view = batView()
    for _ in 0..<90 { view.step() }
    save(view, to: path)
    exit(0)
}

if let path = argument(after: "--game") {
    let smash = batView()
    smash.me.jellyX = smash.bounds.width - blobRadius - 8
    smash.handleAt = CGPoint(x: smash.me.jellyX - 20, y: 340)
    smash.angle = -2.6
    smash.grab(.handle, at: smash.handle)
    smash.lastBarrel = smash.barrel
    var saved = false
    for _ in 0..<120 {
        smash.step()
        if !saved && smash.boinks > 0 {
            for _ in 0..<10 { smash.step() }
            save(smash, to: path)
            saved = true
        }
    }

    let chase = batView()
    let startX = chase.me.jellyX
    chase.grab(.handle, at: chase.handle)
    for frame in 0..<90 { chase.heldAt.x += frame < 60 ? 4 : 0; chase.step() }
    let fled = chase.me.jellyX - startX

    let whip = batView()
    whip.handleAt = CGPoint(x: whip.handleAt.x, y: 380)
    whip.angle = 0
    whip.grab(.handle, at: whip.handle)
    for _ in 0..<60 { whip.step() }
    for _ in 0..<8 { whip.heldAt.x += 25; whip.step() }
    let lag = whip.angle
    for _ in 0..<40 { whip.step() }

    let corner = batView()
    corner.me.jellyX = corner.bounds.width - blobRadius - 8
    corner.handleAt = CGPoint(x: corner.me.jellyX - 120, y: 400)
    corner.angle = 0
    corner.grab(.handle, at: corner.handle)
    var dashed = false
    for _ in 0..<150 { corner.step(); dashed = dashed || corner.isDashing }

    print("smash: boinks \(smash.boinks); chase: jelly moved \(Int(fled)) px away; whip: barrel trails a fast hand by \(Int(-lag * 180 / .pi))°, settles to \(Int(whip.angle * 180 / .pi))°; cornered jelly dashed: \(dashed)")
    exit(0)
}

if let path = argument(after: "--rage") {
    let tide = batView()
    tide.me.rage = 0.55
    for _ in 0..<30 { tide.step() }
    save(tide, to: path + "-half.png")

    let leap = batView()
    leap.me.jellyX = leap.bounds.midX + 100
    leap.me.rage = 1
    var phases: [String] = []
    var shotWindup = false
    var shotLeap = false
    for _ in 0..<200 {
        leap.step()
        let name = "\(leap.me.fury)"
        if phases.last != name { phases.append(name) }
        if leap.me.fury == .windup && leap.age(leap.me.furyAt) > 0.5 && !shotWindup { save(leap, to: path + "-windup.png"); shotWindup = true }
        if leap.me.fury == .leap && leap.me.lift > 60 && !shotLeap { save(leap, to: path + "-leap.png"); shotLeap = true }
    }

    let spit = batView()
    spit.me.jellyX = spit.bounds.width - blobRadius - 8
    spit.handleAt = CGPoint(x: 120, y: 420)
    spit.me.rage = 1
    var spitShot = false
    for _ in 0..<200 {
        spit.step()
        if spit.me.slime != nil && !spitShot && spit.age(spit.me.furyAt) > 0.25 { save(spit, to: path + "-spit.png"); spitShot = true }
    }

    let counter = batView()
    counter.me.fury = .stunned
    counter.me.furyAt = counter.clock
    counter.boink(velocity: CGVector(dx: 0, dy: -900))
    print("leap phases: \(phases.joined(separator: " -> ")), jelly hits \(leap.jellyHits)")
    print("spit: slimed \(spit.isSlimed || spit.jellyHits > 0), jelly hits \(spit.jellyHits)")
    print("counter boink while stunned: score \(counter.score) (a normal boink of that speed scores \(counter.hitPoints))")
    exit(0)
}

if let path = argument(after: "--combo") {
    let view = batView()
    view.me.jellyX = view.bounds.midX + 60
    view.handleAt = CGPoint(x: view.me.jellyX - 60, y: 380)
    view.angle = 0.5
    for hit in 1...8 where !view.isKO {
        view.boink(velocity: CGVector(dx: 200, dy: hit < 4 ? -620 : -1100))
        for _ in 0..<14 { view.step() }
        if hit == 3 { save(view, to: path + "-triple.png") }
    }
    for _ in 0..<6 { view.step() }
    save(view, to: path + "-ko.png")
    print("combo \(view.bestCombo), score \(view.score), K.O.s \(view.kos), health \(Int(view.me.health)), best \(view.best)")
    for _ in 0..<200 { view.step() }
    print("after 3s: slimes left \(view.blobs.count), now on level \(view.level), next slime size \(view.blobs.first.map { String(format: "%.2f", $0.size) } ?? "-")")
    exit(0)
}

if let path = argument(after: "--slice") {
    let view = batView()
    view.arm(.katana)
    view.me.jellyX = view.bounds.width - blobRadius - 8
    view.handleAt = CGPoint(x: view.me.jellyX - 40, y: 330)
    view.angle = -2.2
    view.grab(.barrel, at: view.barrel)
    var saved = false
    for frame in 0..<60 {
        let swing = -2.2 + CGFloat(frame) * 0.16
        view.heldAt = CGPoint(x: view.handle.x + sin(swing) * 175, y: view.handle.y - cos(swing) * 175)
        view.step()
        if !saved && view.slices > 0 && view.age(view.slicedAt) > 0.2 { save(view, to: path); saved = true }
    }
    print("katana: slices \(view.slices), boinks \(view.boinks), score \(view.score), slimes \(view.blobs.map { String(format: "%.2f", $0.size) })")
    exit(0)
}

if let path = argument(after: "--saber") {
    let view = batView()
    view.arm(.saber)
    view.me.jellyX = view.bounds.width - blobRadius - 8
    view.handleAt = CGPoint(x: view.me.jellyX - 40, y: 330)
    view.angle = -2.2
    view.grab(.barrel, at: view.barrel)
    var saved = false
    for frame in 0..<60 {
        let swing = -2.2 + CGFloat(frame) * 0.16
        view.heldAt = CGPoint(x: view.handle.x + sin(swing) * 170, y: view.handle.y - cos(swing) * 170)
        view.step()
        if !saved && view.slices > 0 && view.age(view.slicedAt) > 0.3 { save(view, to: path); saved = true }
    }
    print("saber: slices \(view.slices), seared by saber \(view.cutWeapon == .saber)")
    exit(0)
}

if let path = argument(after: "--axe") {
    let view = batView()
    view.arm(.axe)
    let center = CGPoint(x: view.bounds.midX, y: groundHeight + 230)
    view.handleAt = center
    view.grab(.handle, at: view.handle)
    var topSpin: CGFloat = 0
    var whirlFrames = 0
    var saved = false
    for frame in 0..<240 {
        let turn = CGFloat(frame) * 0.2
        view.heldAt = CGPoint(x: center.x + cos(turn) * 100, y: center.y + sin(turn) * 100)
        view.step()
        topSpin = max(topSpin, abs(view.spin))
        if view.isWhirling { whirlFrames += 1 }
        if !saved && view.isWhirling && view.boinks > 0 { save(view, to: path); saved = true }
    }
    if !saved { save(view, to: path) }
    print("axe: top spin \(Int(topSpin)), whirling \(whirlFrames) frames, chops \(view.boinks), slimes \(view.blobs.count), score \(view.score)")
    exit(whirlFrames > 0 && view.boinks > 0 ? 0 : 1)
}

if let path = argument(after: "--juggle") {
    func hit(_ velocity: CGVector) -> (damage: Int, points: Int, lift: Int) {
        let view = batView()
        view.boink(velocity: velocity)
        var peak: CGFloat = 0
        for _ in 0..<60 { view.step(); peak = max(peak, view.me.lift) }
        return (Int(view.me.maxHealth - view.me.health), view.score, Int(peak))
    }
    let poke = hit(CGVector(dx: 0, dy: -470))
    let swing = hit(CGVector(dx: 300, dy: 1300))
    print("poke: damage \(poke.damage), points \(poke.points), height \(poke.lift)")
    print("swing: damage \(swing.damage), points \(swing.points), height \(swing.lift)")

    let view = batView()
    view.me.jellyX = view.bounds.midX
    var saved = false
    var airHits = 0
    view.boink(velocity: CGVector(dx: 0, dy: 1300))
    for _ in 0..<5 {
        for _ in 0..<200 where !view.blobs.isEmpty && (view.me.liftSpeed > -150 || view.me.lift > 60) { view.step() }
        guard !view.blobs.isEmpty, view.isAirborne, !view.isKO else { break }
        view.me.boinkedAt = -1000
        view.boink(velocity: CGVector(dx: 0, dy: 900))
        airHits = max(airHits, view.blobs.first?.airHits ?? 0)
        if !saved && view.me.airHits >= 2 { for _ in 0..<8 { view.step() }; save(view, to: path); saved = true }
    }
    print("juggle: air hits \(airHits), combo \(view.bestCombo), K.O.s \(view.kos)")
    exit(0)
}

if let path = argument(after: "--levels") {
    let view = batView()
    var cleared: [String] = []
    for _ in 1...3 {
        while view.blobs.contains(where: { !$0.isGone }) {
            view.current = view.blobs.firstIndex { !$0.isGone }!
            view.me.boinkedAt = -1000
            view.boink(velocity: CGVector(dx: 0, dy: 900), slicingAt: view.bodyCenter)
        }
        let before = view.score
        let level = view.level
        for frame in 0..<800 where view.level == level {
            if view.isShopping { view.leaveShop() }
            view.step()
            if view.blobs.isEmpty && frame % 10 == 0 { save(view, to: path + "-between.png") }
        }
        cleared.append("L\(level) +\(view.score - before)")
    }
    print("levels: \(cleared.joined(separator: ", ")), slices \(view.slices), now level \(view.level) size \(String(format: "%.2f", view.me.size))")
    save(view, to: path + "-level.png")

    view.arm(.katana)
    view.me.boinkedAt = -1000
    view.boink(velocity: CGVector(dx: 0, dy: 900), slicingAt: view.bodyCenter)
    for _ in 0..<40 { view.step() }
    save(view, to: path + "-split.png")
    for _ in 0..<Int(view.levelTime / tick) + 120 where !view.isGameOver { view.step() }
    for _ in 0..<90 { view.step() }
    save(view, to: path + "-over.png")
    print("time's up: game over \(view.isGameOver), slimes left \(view.blobs.count), level \(view.level)")
    exit(0)
}

if let path = argument(after: "--fish") {
    let view = batView()
    view.arm(.fish)
    view.me.jellyX = view.bounds.width - blobRadius - 8
    view.handleAt = CGPoint(x: view.me.jellyX - 20, y: 330)
    view.angle = -2.6
    view.grab(.handle, at: view.handle)
    view.lastBarrel = view.barrel
    var saved = false
    for _ in 0..<120 {
        view.step()
        if !saved && view.boinks > 0 && view.sinceBoink > 0.12 { save(view, to: path); saved = true }
    }
    print("fish: slaps \(view.boinks), word \(view.hitWeapon.hit)")
    exit(0)
}

if let path = argument(after: "--vibe") {
    let view = BoinkView(frame: NSRect(origin: .zero, size: windowSize))
    for _ in 0..<120 { view.step() }
    let frozen = (view.clock, view.timeLeft)
    view.toggleVibe()
    for _ in 0..<200 { view.vibeClock += tick }
    save(view, to: path)
    view.blowsBubbles = false
    save(view, to: path + "-smoke.png")
    view.toggleVibe()
    print("vibe keeps clock \(view.clock == frozen.0), time left \(view.timeLeft == frozen.1)")
    exit(view.clock == frozen.0 && !view.isVibing ? 0 : 1)
}

if let level = argument(after: "--bench").flatMap({ Int($0) }) {
    let view = batView()
    view.startLevel(level)
    var hits = 0
    while hits < 200, let index = view.blobs.firstIndex(where: { !$0.isGone && $0.size >= minSplitSize }) {
        view.current = index
        view.me.boinkedAt = -1000
        view.me.health = 1000
        view.boink(velocity: CGVector(dx: 0, dy: 600), slicingAt: view.bodyCenter)
        hits += 1
    }
    view.popups = []
    view.particles = []
    view.bursts = []
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    let start = Date()
    for _ in 0..<300 {
        view.step()
        view.levelAt = view.clock
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }
    let perFrame = Date().timeIntervalSince(start) / 300 * 1000
    print("level \(level): \(view.blobs.count) slimes, \(String(format: "%.2f", perFrame)) ms per frame")
    exit(0)
}

if let path = argument(after: "--smash") {
    func knocked(_ weapon: Weapon, _ velocity: CGVector) -> (slid: Int, peak: Int) {
        let view = batView()
        view.arm(weapon)
        view.me.jellyX = 200
        view.boink(velocity: velocity)
        var peak: CGFloat = 0
        for _ in 0..<150 { view.step(); peak = max(peak, view.me.lift) }
        return (Int(view.me.jellyX - 200), Int(peak))
    }
    for (name, velocity) in [("side", CGVector(dx: 1200, dy: 0)), ("up", CGVector(dx: 300, dy: 1200)), ("slam", CGVector(dx: 200, dy: -1200))] {
        let bat = knocked(.bat, velocity)
        let fish = knocked(.fish, velocity)
        print("\(name): bat slides \(bat.slid) px, peaks \(bat.peak) px; fish slides \(fish.slid) px, peaks \(fish.peak) px")
    }

    let view = batView()
    view.blobs = [Blob(at: 200), Blob(at: 520)]
    view.current = 0
    view.boink(velocity: CGVector(dx: 1400, dy: 0))
    var saved = false
    var bowled = false
    for _ in 0..<180 {
        let score = view.score
        view.step()
        if !bowled && view.score > score { bowled = true }
        if !saved && view.blobs.count > 1 && view.blobs[1].jellySpeed > 200 { for _ in 0..<4 { view.step() }; save(view, to: path); saved = true }
    }
    print("bowl: second slime pushed to x \(view.blobs.map { Int($0.jellyX) }), health \(view.blobs.map { Int($0.health) }), combo \(view.bestCombo), K.O.s \(view.kos)")
    exit(0)
}

if let path = argument(after: "--shop") {
    let view = batView()
    view.boink(velocity: CGVector(dx: 0, dy: -1500))
    view.me.health = 0
    view.knockOut()
    for _ in 0..<200 where !view.isShopping { view.step() }
    let earned = view.gold
    view.gold += 100
    view.buy(.weapon(.katana))
    view.buy(.upgrade(.power))
    view.buy(.upgrade(.power))
    view.buy(.weapon(.katana))
    for _ in 0..<10 { view.step() }
    save(view, to: path)
    let shopping = view.isShopping
    view.leaveShop()
    for frame in 0..<400 where view.isCountingDown {
        view.step()
        if frame == 150 { save(view, to: path + "-countdown.png") }
    }
    print("earned \(earned) gold on level 1, shop open \(shopping); after buying: \(view.gold) gold, weapon \(view.weapon), power rank \(view.rank(.power)); next level \(view.level), \(view.blobs.count) slimes")
    exit(shopping && view.weapon == .katana && view.rank(.power) == 2 && view.gold == earned + 100 - 40 - 20 - 40 ? 0 : 1)
}

if let path = argument(after: "--forge") {
    let view = batView()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 1120, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 900, height: 560)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedWhite: 0.2, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 900, height: 560).fill()
    for (row, choice) in Weapon.all.enumerated() {
        for grade in 0..<3 {
            view.weapon = choice
            view.tiers[choice] = grade
            view.handleAt = CGPoint(x: 60 + CGFloat(grade) * 290, y: 500 - CGFloat(row) * 105)
            view.angle = .pi / 2
            switch choice {
            case .bat: view.drawBat()
            case .katana: view.drawKatana()
            case .saber: view.drawSaber()
            case .fish: view.drawFish()
            case .axe: view.drawAxe()
            }
            drawText(choice.tierNames[grade], at: CGPoint(x: view.handleAt.x + 80, y: view.handleAt.y - 48), size: 13, color: .white, weight: .bold)
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))

    let shop = batView()
    shop.tiers = [:]
    shop.gold = 1000
    let prices = (0..<3).compactMap { _ -> Int? in
        let cost = shop.price(.forge(.bat))
        shop.buy(.forge(.bat))
        return cost
    }
    shop.boink(velocity: CGVector(dx: 0, dy: -900))
    let forged = shop.me.maxHealth - shop.me.health
    let plain = batView()
    plain.boink(velocity: CGVector(dx: 0, dy: -900))
    let base = plain.me.maxHealth - plain.me.health
    print("bat forge prices \(prices), now \(shop.weapon.tierNames[shop.tier(.bat)]); damage \(String(format: "%.1f", base)) -> \(String(format: "%.1f", forged))")
    exit(prices.count == 2 && prices[1] > prices[0] && abs(forged / base - 1.2) < 0.01 ? 0 : 1)
}

if let path = argument(after: "--stress") {
    let view = batView()
    var folded = 0
    for frame in 0..<1200 {
        let t = CGFloat(frame) / 60
        if frame == 0 { view.grab(.handle, at: view.handle) }
        if frame < 450 {
            view.heldAt = CGPoint(x: view.bounds.midX + sin(t * 2.1) * 330, y: 330 + sin(t * 4.2) * 60)
        } else if frame == 450 {
            view.held = nil
            view.grab(.barrel, at: view.barrel)
        } else if frame < 900 {
            view.heldAt = CGPoint(x: view.handle.x + cos(t * 7) * 160, y: view.handle.y + sin(t * 7) * 160)
        } else {
            view.held = nil
        }
        if frame == 300 { view.arm(.katana) }
        view.step()
        if frame % 4 == 0 { save(view, to: path) }
        folded += view.blobs.contains { crossings($0.jelly.points) > 0 } ? 1 : 0
    }
    print("folded frames: \(folded) of 1200, level \(view.level), slimes \(view.blobs.count), slices \(view.slices), boinks \(view.boinks), dodges \(view.dodges), jelly hits \(view.jellyHits), K.O.s \(view.kos), score \(view.score)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
