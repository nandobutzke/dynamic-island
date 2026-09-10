import Foundation

@MainActor
final class LifestyleNudgeProvider: NudgeProvider {
    let source: NudgeSource = .lifestyle

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func currentNudges() async -> [Nudge] {
        let instant = now()
        let eligible = Kind.allCases.filter { kind in
            kind.isEligible(at: instant) && isCooledDown(kind, at: instant)
        }.filter { _ in
            isAnyCooledDown(at: instant)
        }

        let ranked = eligible.map { kind -> (Kind, NudgePriority, Double) in
            (kind, kind.priority(at: instant), kind.weight(at: instant))
        }
        guard let topPriority = ranked.map(\.1).max() else { return [] }
        let band = ranked.filter { $0.1 == topPriority }
        guard let picked = weightedPick(band) else { return [] }

        let templates = picked.templates
        let lastIndex = defaults.integer(forKey: templateKey(picked))
        let index = templates.isEmpty ? 0 : lastIndex % templates.count
        let template = templates[index]

        return [
            Nudge(
                id: picked.nudgeID,
                source: .lifestyle,
                emoji: picked.emoji,
                title: template.title,
                description: template.description,
                priority: picked.priority(at: instant),
                createdAt: instant
            )
        ]
    }

    func didPresent(_ nudge: Nudge) {
        let instant = now()
        defaults.set(instant.timeIntervalSince1970, forKey: lastAnyKey)
        guard let kind = Kind.allCases.first(where: { $0.nudgeID == nudge.id }) else { return }
        defaults.set(instant.timeIntervalSince1970, forKey: lastShownKey(kind))
        let templates = kind.templates
        let lastIndex = defaults.integer(forKey: templateKey(kind))
        let next = templates.isEmpty ? 0 : (lastIndex + 1) % templates.count
        defaults.set(next, forKey: templateKey(kind))
    }

    private func isCooledDown(_ kind: Kind, at date: Date) -> Bool {
        let last = defaults.double(forKey: lastShownKey(kind))
        guard last > 0 else { return true }
        let elapsed = date.timeIntervalSince1970 - last
        return elapsed >= kind.cooldownTicks * NudgeSchedule.popInterval
    }

    private func isAnyCooledDown(at date: Date) -> Bool {
        let last = defaults.double(forKey: lastAnyKey)
        guard last > 0 else { return true }
        return date.timeIntervalSince1970 - last >= 2 * NudgeSchedule.popInterval
    }

    private func weightedPick(_ items: [(Kind, NudgePriority, Double)]) -> Kind? {
        let total = items.reduce(0) { $0 + $1.2 }
        guard total > 0 else { return items.first?.0 }
        var slice = Double.random(in: 0..<total)
        for item in items {
            slice -= item.2
            if slice <= 0 { return item.0 }
        }
        return items.last?.0
    }

    private var lastAnyKey: String { "nudge.lifestyle.lastAny" }
    private func lastShownKey(_ kind: Kind) -> String { "nudge.lifestyle.lastShown.\(kind.rawValue)" }
    private func templateKey(_ kind: Kind) -> String { "nudge.lifestyle.lastTemplate.\(kind.rawValue)" }
}

private struct LifestyleTemplate {
    let title: String
    let description: String
}

private enum Kind: String, CaseIterable {
    case water, chores, stretch, reading, study

    var nudgeID: String { "lifestyle.\(rawValue)" }

    var emoji: String {
        switch self {
        case .water: return "💧"
        case .chores: return "🧹"
        case .stretch: return "🧘"
        case .reading: return "📖"
        case .study: return "📚"
        }
    }

    var cooldownTicks: TimeInterval {
        switch self {
        case .water: return 3
        case .stretch, .study: return 4
        case .chores, .reading: return 6
        }
    }

    /// Study only at lunch (12:00–13:00) and after work (19:00–23:00). Other kinds always eligible.
    func isEligible(at date: Date) -> Bool {
        switch self {
        case .water, .chores, .stretch, .reading:
            return true
        case .study:
            let hour = Calendar.current.component(.hour, from: date)
            let isNoon = hour == 12
            let isNight = hour >= 19 && hour < 23
            return isNoon || isNight
        }
    }

    func priority(at _: Date) -> NudgePriority {
        switch self {
        case .water, .stretch: return .medium
        case .chores, .reading: return .low
        case .study: return .high
        }
    }

    func weight(at _: Date) -> Double {
        switch self {
        case .water: return 3.0
        case .stretch: return 2.0
        case .study: return 2.4
        case .chores: return 1.4
        case .reading: return 1.3
        }
    }

    var templates: [LifestyleTemplate] {
        switch self {
        case .water:
            return [
                .init(title: "Hora de hidratar", description: "Já faz um tempo sem um copo d'água"),
                .init(title: "Bebe água", description: "Um gole agora rende mais que esperar a sede"),
                .init(title: "Pausa d'água", description: "Enche o copo e volta em 30 segundos"),
                .init(title: "Hidratação", description: "Mais um copo antes de seguir o fluxo")
            ]
        case .chores:
            return [
                .init(title: "Casa", description: "Uma tarefa rápida: louça ou 5 min de organização"),
                .init(title: "Doméstico", description: "Tira 2 minutos: lixo, pia ou uma superfície"),
                .init(title: "Organizar", description: "Um canto da mesa já muda o resto do dia"),
                .init(title: "Casa rápida", description: "Estende a roupa ou recolhe o que está à vista")
            ]
        case .stretch:
            return [
                .init(title: "Alongamento", description: "Levanta, ombros e pescoço por 1 minuto"),
                .init(title: "Move o corpo", description: "Rola os ombros e estica os pulsos agora"),
                .init(title: "Postura", description: "Sobe da cadeira e abre o peito uns 60 segundos"),
                .init(title: "Pausa física", description: "Pescoço, lombar e pernas — vale o minuto")
            ]
        case .reading:
            return [
                .init(title: "Leitura", description: "10 páginas ou 5 minutos no livro"),
                .init(title: "Ler um pouco", description: "Abre o livro só até o próximo parágrafo"),
                .init(title: "Página extra", description: "Cinco minutos de leitura sem tela"),
                .init(title: "Livro", description: "Troca o feed por um capítulo curto")
            ]
        case .study:
            return [
                .init(title: "Faculdade", description: "Revisa uma disciplina 15 minutos"),
                .init(title: "Estudar", description: "Um exercício ou um resumo curto agora"),
                .init(title: "Matéria", description: "Reabre o caderno numa disciplina pendente"),
                .init(title: "Revisão", description: "15 minutos focados valem mais que adiar")
            ]
        }
    }
}
