// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct CleanerExclusionStrings {
    /// Shown in the result list's per-item context menu.
    let excludeAction: String
    let listTitle: String
    let caption: String
    let removeButton: String
    let pathsHeader: String
    let appsHeader: String
}

extension FeatureStrings {
    static func cleanerExclusions(_ language: AppLanguage) -> CleanerExclusionStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension CleanerExclusionStrings {
    static let enUS = CleanerExclusionStrings(
        excludeAction: "Never scan this again",
        listTitle: "Cleaner exclusions",
        caption: "Paths and apps you've excluded stay out of every future scan, on top of the built-in safety rules.",
        removeButton: "Remove",
        pathsHeader: "Excluded paths",
        appsHeader: "Excluded apps"
    )

    static let ptBR = CleanerExclusionStrings(
        excludeAction: "Nunca escanear isto novamente",
        listTitle: "Exclusões do limpador",
        caption: "Caminhos e apps que você excluiu ficam fora de toda futura verificação, além das regras de segurança internas.",
        removeButton: "Remover",
        pathsHeader: "Caminhos excluídos",
        appsHeader: "Apps excluídos"
    )

    static let tr = CleanerExclusionStrings(
        excludeAction: "Bunu bir daha tarama",
        listTitle: "Temizleyici hariç tutmaları",
        caption: "Hariç tuttuğunuz yollar ve uygulamalar, yerleşik güvenlik kurallarına ek olarak her gelecekteki taramanın dışında kalır.",
        removeButton: "Kaldır",
        pathsHeader: "Hariç tutulan yollar",
        appsHeader: "Hariç tutulan uygulamalar"
    )

    static let ru = CleanerExclusionStrings(
        excludeAction: "Больше не сканировать это",
        listTitle: "Исключения очистки",
        caption: "Исключённые пути и приложения не попадают ни в одно будущее сканирование, в дополнение к встроенным правилам безопасности.",
        removeButton: "Удалить",
        pathsHeader: "Исключённые пути",
        appsHeader: "Исключённые приложения"
    )

    static let es = CleanerExclusionStrings(
        excludeAction: "No volver a escanear esto",
        listTitle: "Exclusiones del limpiador",
        caption: "Las rutas y apps que excluyas quedan fuera de todos los futuros escaneos, además de las reglas de seguridad integradas.",
        removeButton: "Quitar",
        pathsHeader: "Rutas excluidas",
        appsHeader: "Apps excluidas"
    )

    static let de = CleanerExclusionStrings(
        excludeAction: "Dies nie wieder scannen",
        listTitle: "Cleaner-Ausnahmen",
        caption: "Ausgeschlossene Pfade und Apps bleiben bei jedem zukünftigen Scan außen vor, zusätzlich zu den integrierten Sicherheitsregeln.",
        removeButton: "Entfernen",
        pathsHeader: "Ausgeschlossene Pfade",
        appsHeader: "Ausgeschlossene Apps"
    )

    static let fr = CleanerExclusionStrings(
        excludeAction: "Ne plus jamais analyser ceci",
        listTitle: "Exclusions du nettoyeur",
        caption: "Les chemins et apps exclus restent hors de chaque future analyse, en plus des règles de sécurité intégrées.",
        removeButton: "Retirer",
        pathsHeader: "Chemins exclus",
        appsHeader: "Apps exclues"
    )

    static let it = CleanerExclusionStrings(
        excludeAction: "Non scansionare mai più questo",
        listTitle: "Esclusioni del pulitore",
        caption: "I percorsi e le app esclusi restano fuori da ogni futura scansione, in aggiunta alle regole di sicurezza integrate.",
        removeButton: "Rimuovi",
        pathsHeader: "Percorsi esclusi",
        appsHeader: "App escluse"
    )

    static let ja = CleanerExclusionStrings(
        excludeAction: "今後スキャンしない",
        listTitle: "クリーナーの除外",
        caption: "除外したパスとAppは、組み込みの安全ルールに加えて、今後のすべてのスキャンから除外されます。",
        removeButton: "削除",
        pathsHeader: "除外されたパス",
        appsHeader: "除外されたApp"
    )

    static let ko = CleanerExclusionStrings(
        excludeAction: "다시 검사하지 않기",
        listTitle: "클리너 제외 목록",
        caption: "제외한 경로와 앱은 내장된 안전 규칙에 더해 이후의 모든 검사에서 제외됩니다.",
        removeButton: "제거",
        pathsHeader: "제외된 경로",
        appsHeader: "제외된 앱"
    )

    static let zhHans = CleanerExclusionStrings(
        excludeAction: "以后不再扫描此项",
        listTitle: "清理排除项",
        caption: "除内置的安全规则外，被排除的路径和 App 也不会出现在以后的任何扫描中。",
        removeButton: "移除",
        pathsHeader: "已排除的路径",
        appsHeader: "已排除的 App"
    )

    static let zhTW = CleanerExclusionStrings(
        excludeAction: "以後不再掃描此項",
        listTitle: "清理排除項目",
        caption: "除了內建的安全規則外，被排除的路徑與 App 也不會出現在以後的任何掃描中。",
        removeButton: "移除",
        pathsHeader: "已排除的路徑",
        appsHeader: "已排除的 App"
    )

    static let zhHK = CleanerExclusionStrings(
        excludeAction: "以後不再掃描此項",
        listTitle: "清理排除項目",
        caption: "除了內建的安全規則外，被排除的路徑與 App 也不會出現在以後的任何掃描中。",
        removeButton: "移除",
        pathsHeader: "已排除的路徑",
        appsHeader: "已排除的 App"
    )
}
