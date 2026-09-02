// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the notch media controls widget.
struct NotchMediaFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let toggleLabel: String
    let idlePillToggleLabel: String
    let idlePillCaption: String
    let nowPlayingFallback: String
    let openAppFormat: String
    let noSourceCaption: String
}

extension FeatureStrings {
    static func notchMedia(_ language: AppLanguage) -> NotchMediaFeatureStrings {
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

extension NotchMediaFeatureStrings {
    static let enUS = NotchMediaFeatureStrings(
        pageTitle: "Notch media controls",
        hubDescription: "A Dynamic-Island-style now-playing widget at the notch",
        panelCaption: "Shows a small pill at the notch (or the menu bar on Macs without one) that expands into playback controls",
        toggleLabel: "Show notch media controls",
        idlePillToggleLabel: "Show a slim pill while something is playing",
        idlePillCaption: "Off hides the widget completely until you hover or click near it",
        nowPlayingFallback: "Now Playing",
        openAppFormat: "Open %@",
        noSourceCaption: "Nothing is playing"
    )

    static let ptBR = NotchMediaFeatureStrings(
        pageTitle: "Controles de mídia no notch",
        hubDescription: "Um widget de reprodução no estilo Dynamic Island, no notch",
        panelCaption: "Mostra uma pequena pílula no notch (ou na barra de menus em Macs sem notch) que se expande em controles de reprodução",
        toggleLabel: "Mostrar controles de mídia no notch",
        idlePillToggleLabel: "Mostrar uma pílula fina enquanto algo está tocando",
        idlePillCaption: "Desativado esconde o widget completamente até você passar o mouse ou clicar perto dele",
        nowPlayingFallback: "Tocando agora",
        openAppFormat: "Abrir %@",
        noSourceCaption: "Nada está tocando"
    )

    static let tr = NotchMediaFeatureStrings(
        pageTitle: "Çentik medya kontrolleri",
        hubDescription: "Çentikte Dynamic Island tarzında bir şu an çalıyor widget'ı",
        panelCaption: "Çentikte (veya çentiği olmayan Mac'lerde menü çubuğunda) küçük bir hap gösterir ve genişleyerek oynatma kontrollerini açar",
        toggleLabel: "Çentik medya kontrollerini göster",
        idlePillToggleLabel: "Bir şeyler çalarken ince bir hap göster",
        idlePillCaption: "Kapalıyken, üzerine gelene veya tıklayana kadar widget tamamen gizlenir",
        nowPlayingFallback: "Şu An Çalıyor",
        openAppFormat: "%@ uygulamasını aç",
        noSourceCaption: "Hiçbir şey çalmıyor"
    )

    static let ru = NotchMediaFeatureStrings(
        pageTitle: "Управление медиа в вырезе",
        hubDescription: "Виджет «Сейчас играет» в стиле Dynamic Island возле выреза экрана",
        panelCaption: "Показывает небольшую капсулу у выреза (или в строке меню на Mac без выреза), которая разворачивается в элементы управления воспроизведением",
        toggleLabel: "Показывать управление медиа в вырезе",
        idlePillToggleLabel: "Показывать тонкую капсулу во время воспроизведения",
        idlePillCaption: "При выключении виджет полностью скрыт, пока вы не наведёте курсор или не нажмёте рядом",
        nowPlayingFallback: "Сейчас играет",
        openAppFormat: "Открыть %@",
        noSourceCaption: "Ничего не воспроизводится"
    )

    static let es = NotchMediaFeatureStrings(
        pageTitle: "Controles multimedia del notch",
        hubDescription: "Un widget de reproducción al estilo Dynamic Island en el notch",
        panelCaption: "Muestra una pequeña píldora en el notch (o en la barra de menús en Macs sin notch) que se expande con controles de reproducción",
        toggleLabel: "Mostrar controles multimedia del notch",
        idlePillToggleLabel: "Mostrar una píldora fina mientras algo se reproduce",
        idlePillCaption: "Desactivado oculta el widget por completo hasta que pases el cursor o hagas clic cerca",
        nowPlayingFallback: "Reproduciendo",
        openAppFormat: "Abrir %@",
        noSourceCaption: "No se está reproduciendo nada"
    )

    static let de = NotchMediaFeatureStrings(
        pageTitle: "Notch-Mediensteuerung",
        hubDescription: "Ein Dynamic-Island-artiges Now-Playing-Widget an der Notch",
        panelCaption: "Zeigt eine kleine Pille an der Notch (oder in der Menüleiste bei Macs ohne Notch), die sich zu Wiedergabesteuerungen erweitert",
        toggleLabel: "Notch-Mediensteuerung anzeigen",
        idlePillToggleLabel: "Schmale Pille anzeigen, während etwas abgespielt wird",
        idlePillCaption: "Aus blendet das Widget vollständig aus, bis du in die Nähe fährst oder klickst",
        nowPlayingFallback: "Läuft gerade",
        openAppFormat: "%@ öffnen",
        noSourceCaption: "Es wird nichts wiedergegeben"
    )

    static let fr = NotchMediaFeatureStrings(
        pageTitle: "Contrôles média de l'encoche",
        hubDescription: "Un widget de lecture en cours façon Dynamic Island au niveau de l'encoche",
        panelCaption: "Affiche une petite pilule au niveau de l'encoche (ou dans la barre de menus sur les Mac sans encoche) qui se déploie en contrôles de lecture",
        toggleLabel: "Afficher les contrôles média de l'encoche",
        idlePillToggleLabel: "Afficher une fine pilule pendant la lecture",
        idlePillCaption: "Désactivé masque entièrement le widget jusqu'à ce que vous surviez ou cliquiez à proximité",
        nowPlayingFallback: "Lecture en cours",
        openAppFormat: "Ouvrir %@",
        noSourceCaption: "Rien n'est en cours de lecture"
    )

    static let it = NotchMediaFeatureStrings(
        pageTitle: "Controlli multimediali del notch",
        hubDescription: "Un widget di riproduzione in stile Dynamic Island sul notch",
        panelCaption: "Mostra una piccola pillola sul notch (o sulla barra dei menu nei Mac senza notch) che si espande in controlli di riproduzione",
        toggleLabel: "Mostra i controlli multimediali del notch",
        idlePillToggleLabel: "Mostra una pillola sottile durante la riproduzione",
        idlePillCaption: "Disattivato nasconde completamente il widget finché non passi con il cursore o clicchi nelle vicinanze",
        nowPlayingFallback: "In riproduzione",
        openAppFormat: "Apri %@",
        noSourceCaption: "Non è in riproduzione nulla"
    )

    static let ja = NotchMediaFeatureStrings(
        pageTitle: "ノッチメディアコントロール",
        hubDescription: "ノッチにDynamic Island風の再生中ウィジェットを表示",
        panelCaption: "ノッチ（ノッチのないMacではメニューバー）に小さなピルを表示し、展開すると再生コントロールになります",
        toggleLabel: "ノッチメディアコントロールを表示",
        idlePillToggleLabel: "再生中は細いピルを表示",
        idlePillCaption: "オフにすると、近くにカーソルを合わせるかクリックするまでウィジェットは完全に非表示になります",
        nowPlayingFallback: "再生中",
        openAppFormat: "%@ を開く",
        noSourceCaption: "再生中のものはありません"
    )

    static let ko = NotchMediaFeatureStrings(
        pageTitle: "노치 미디어 컨트롤",
        hubDescription: "노치에 표시되는 Dynamic Island 스타일의 재생 중 위젯",
        panelCaption: "노치(노치가 없는 Mac에서는 메뉴 막대)에 작은 알약 모양을 표시하며, 확장하면 재생 컨트롤이 나타납니다",
        toggleLabel: "노치 미디어 컨트롤 표시",
        idlePillToggleLabel: "재생 중일 때 얇은 알약 표시",
        idlePillCaption: "끄면 근처에 마우스를 올리거나 클릭할 때까지 위젯이 완전히 숨겨집니다",
        nowPlayingFallback: "현재 재생 중",
        openAppFormat: "%@ 열기",
        noSourceCaption: "재생 중인 항목이 없습니다"
    )

    static let zhHans = NotchMediaFeatureStrings(
        pageTitle: "灵动岛式刘海媒体控制",
        hubDescription: "在刘海处显示灵动岛风格的正在播放小组件",
        panelCaption: "在刘海处（没有刘海的 Mac 上则在菜单栏）显示一个小药丸，展开后即为播放控制",
        toggleLabel: "显示刘海媒体控制",
        idlePillToggleLabel: "播放时显示纤细的药丸提示",
        idlePillCaption: "关闭后小组件将完全隐藏，直到你将指针移近或点击附近区域",
        nowPlayingFallback: "正在播放",
        openAppFormat: "打开 %@",
        noSourceCaption: "当前没有播放内容"
    )

    static let zhTW = NotchMediaFeatureStrings(
        pageTitle: "動態島式瀏海媒體控制",
        hubDescription: "在瀏海處顯示動態島風格的正在播放小工具",
        panelCaption: "在瀏海處（沒有瀏海的 Mac 則在選單列）顯示一個小藥丸，展開後即為播放控制",
        toggleLabel: "顯示瀏海媒體控制",
        idlePillToggleLabel: "播放時顯示纖細的藥丸提示",
        idlePillCaption: "關閉後小工具將完全隱藏，直到你將指標移近或點按附近區域",
        nowPlayingFallback: "正在播放",
        openAppFormat: "打開 %@",
        noSourceCaption: "目前沒有播放內容"
    )

    static let zhHK = NotchMediaFeatureStrings(
        pageTitle: "動態島式瀏海媒體控制",
        hubDescription: "在瀏海處顯示動態島風格的正在播放小工具",
        panelCaption: "在瀏海處（沒有瀏海的 Mac 則在選單列）顯示一個小藥丸，展開後即為播放控制",
        toggleLabel: "顯示瀏海媒體控制",
        idlePillToggleLabel: "播放時顯示纖細的藥丸提示",
        idlePillCaption: "關閉後小工具將完全隱藏，直到你將指標移近或點按附近區域",
        nowPlayingFallback: "正在播放",
        openAppFormat: "打開 %@",
        noSourceCaption: "目前沒有播放內容"
    )
}
