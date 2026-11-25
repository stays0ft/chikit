// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the screenshot tool.
struct ScreenshotFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let fileNamePrefix: String
    let hintDrag: String
    let hintClick: String
    let folderLabel: String
    let folderChoose: String
    let editorTitle: String
    let textPlaceholder: String
    let cancel: String
    let backdropLabel: String
    let backdropNone: String
    let copyButton: String
    let saveButton: String
    let saveAsButton: String
    let discardTitle: String
    let discardMessage: String
    let copiedHUD: String
    let savedHUDFormat: String
    let backdropPaddingLabel: String
    let backdropWallpaperLabel: String
    let backdropImageButton: String
    let backdropSolidLabel: String
    let backdropGradientLabel: String
    let backdropCornersLabel: String
    let backdropSavePreset: String
    let backdropDeletePreset: String
    let backdropCustomLabel: String
    let openEditorToggle: String
    let openEditorCaption: String
    let backdropBlurLabel: String
    let scrollingCaptureHintOff: String
    let scrollingCaptureHintOn: String
    let done: String
    let scrollingCaptureSelectionHint: String
    let screenCaptureTitle: String
}

extension FeatureStrings {
    static func screenshot(_ language: AppLanguage) -> ScreenshotFeatureStrings {
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

extension ScreenshotFeatureStrings {
    static let enUS = ScreenshotFeatureStrings(
        pageTitle: "Screenshot",
        hubDescription: "Captures an area, window or screen and annotates it",
        panelCaption: "Capture an area, window or the whole screen",
        fileNamePrefix: "Screenshot",
        hintDrag: "Drag to select an area",
        hintClick: "Click a window to capture it",
        folderLabel: "Save to",
        folderChoose: "Choose…",
        editorTitle: "Screenshot",
        textPlaceholder: "Text",
        cancel: "Cancel",
        backdropLabel: "Background",
        backdropNone: "None",
        copyButton: "Copy",
        saveButton: "Save",
        saveAsButton: "Save As…",
        discardTitle: "Discard this screenshot?",
        discardMessage: "It was not copied or saved yet.",
        copiedHUD: "Screenshot copied",
        savedHUDFormat: "Saved to %@",
        backdropPaddingLabel: "Margin",
        backdropWallpaperLabel: "Wallpaper",
        backdropImageButton: "Image…",
        backdropSolidLabel: "Solid",
        backdropGradientLabel: "Gradient",
        backdropCornersLabel: "Corners",
        backdropSavePreset: "Save background",
        backdropDeletePreset: "Remove",
        backdropCustomLabel: "Custom",
        openEditorToggle: "Open the editor right after capturing",
        openEditorCaption: "The capture skips the floating preview and opens ready to annotate.",
        backdropBlurLabel: "Blur",
        scrollingCaptureHintOff: "S toggles scrolling",
        scrollingCaptureHintOn: "Scrolling on",
        done: "Done",
        scrollingCaptureSelectionHint: "Drag only the part of the page that moves.",
        screenCaptureTitle: "Screen capture"
    )

    static let ptBR = ScreenshotFeatureStrings(
        pageTitle: "Captura de tela",
        hubDescription: "Captura uma área, janela ou tela e permite anotar",
        panelCaption: "Capture uma área, uma janela ou a tela inteira",
        fileNamePrefix: "Captura de Tela",
        hintDrag: "Arraste para selecionar uma área",
        hintClick: "Clique numa janela para capturá-la",
        folderLabel: "Salvar em",
        folderChoose: "Escolher…",
        editorTitle: "Captura de tela",
        textPlaceholder: "Texto",
        cancel: "Cancelar",
        backdropLabel: "Fundo",
        backdropNone: "Nenhum",
        copyButton: "Copiar",
        saveButton: "Salvar",
        saveAsButton: "Salvar Como…",
        discardTitle: "Descartar esta captura?",
        discardMessage: "Ela ainda não foi copiada nem salva.",
        copiedHUD: "Captura copiada",
        savedHUDFormat: "Salva em %@",
        backdropPaddingLabel: "Margem",
        backdropWallpaperLabel: "Papel de parede",
        backdropImageButton: "Imagem…",
        backdropSolidLabel: "Sólida",
        backdropGradientLabel: "Gradiente",
        backdropCornersLabel: "Cantos",
        backdropSavePreset: "Salvar fundo",
        backdropDeletePreset: "Remover",
        backdropCustomLabel: "Personalizado",
        openEditorToggle: "Abrir o editor logo após capturar",
        openEditorCaption: "A captura pula a pré-visualização flutuante e já abre pronta para anotar.",
        backdropBlurLabel: "Desfoque",
        scrollingCaptureHintOff: "S alterna rolagem",
        scrollingCaptureHintOn: "Rolagem ligada",
        done: "Concluído",
        scrollingCaptureSelectionHint: "Arraste apenas a parte da página que rola.",
        screenCaptureTitle: "Ferramentas de captura"
    )

    static let tr = ScreenshotFeatureStrings(
        pageTitle: "Ekran görüntüsü",
        hubDescription: "Bir alanı, pencereyi veya ekranı yakalar ve işaretlemenizi sağlar",
        panelCaption: "Bir alanı, bir pencereyi veya tüm ekranı yakalayın",
        fileNamePrefix: "Ekran Görüntüsü",
        hintDrag: "Bir alan seçmek için sürükleyin",
        hintClick: "Yakalamak için bir pencereye tıklayın",
        folderLabel: "Kayıt yeri",
        folderChoose: "Seç…",
        editorTitle: "Ekran görüntüsü",
        textPlaceholder: "Metin",
        cancel: "Vazgeç",
        backdropLabel: "Arka plan",
        backdropNone: "Yok",
        copyButton: "Kopyala",
        saveButton: "Kaydet",
        saveAsButton: "Farklı Kaydet…",
        discardTitle: "Bu ekran görüntüsü silinsin mi?",
        discardMessage: "Henüz kopyalanmadı veya kaydedilmedi.",
        copiedHUD: "Ekran görüntüsü kopyalandı",
        savedHUDFormat: "Şuraya kaydedildi: %@",
        backdropPaddingLabel: "Kenar payı",
        backdropWallpaperLabel: "Duvar kağıdı",
        backdropImageButton: "Görsel…",
        backdropSolidLabel: "Düz",
        backdropGradientLabel: "Degrade",
        backdropCornersLabel: "Köşeler",
        backdropSavePreset: "Arka planı kaydet",
        backdropDeletePreset: "Kaldır",
        backdropCustomLabel: "Özel",
        openEditorToggle: "Yakaladıktan hemen sonra düzenleyiciyi aç",
        openEditorCaption: "Yakalama, yüzen önizlemeyi atlar ve işaretlemeye hazır şekilde açılır.",
        backdropBlurLabel: "Bulanıklık",
        scrollingCaptureHintOff: "S kaydırmayı açar",
        scrollingCaptureHintOn: "Kaydırma açık",
        done: "Bitti",
        scrollingCaptureSelectionHint: "Sayfanın yalnızca kayan bölümünü seçin.",
        screenCaptureTitle: "Ekran yakalama"
    )

    static let ru = ScreenshotFeatureStrings(
        pageTitle: "Снимок экрана",
        hubDescription: "Снимает область, окно или экран и позволяет делать пометки",
        panelCaption: "Снимите область, окно или весь экран",
        fileNamePrefix: "Снимок экрана",
        hintDrag: "Потяните, чтобы выделить область",
        hintClick: "Нажмите на окно, чтобы снять его",
        folderLabel: "Сохранять в",
        folderChoose: "Выбрать…",
        editorTitle: "Снимок экрана",
        textPlaceholder: "Текст",
        cancel: "Отменить",
        backdropLabel: "Фон",
        backdropNone: "Нет",
        copyButton: "Скопировать",
        saveButton: "Сохранить",
        saveAsButton: "Сохранить как…",
        discardTitle: "Удалить этот снимок?",
        discardMessage: "Он ещё не скопирован и не сохранён.",
        copiedHUD: "Снимок скопирован",
        savedHUDFormat: "Сохранено в %@",
        backdropPaddingLabel: "Поля",
        backdropWallpaperLabel: "Обои",
        backdropImageButton: "Изображение…",
        backdropSolidLabel: "Сплошной",
        backdropGradientLabel: "Градиент",
        backdropCornersLabel: "Углы",
        backdropSavePreset: "Сохранить фон",
        backdropDeletePreset: "Удалить",
        backdropCustomLabel: "Свой",
        openEditorToggle: "Открывать редактор сразу после снимка",
        openEditorCaption: "Снимок пропускает плавающее окно предпросмотра и сразу открывается готовым к пометкам.",
        backdropBlurLabel: "Размытие",
        scrollingCaptureHintOff: "S включает прокрутку",
        scrollingCaptureHintOn: "Прокрутка включена",
        done: "Готово",
        scrollingCaptureSelectionHint: "Выделите только прокручиваемую часть страницы.",
        screenCaptureTitle: "Захват экрана"
    )

    static let es = ScreenshotFeatureStrings(
        pageTitle: "Captura de pantalla",
        hubDescription: "Captura un área, ventana o pantalla y permite anotarla",
        panelCaption: "Captura un área, una ventana o toda la pantalla",
        fileNamePrefix: "Captura de pantalla",
        hintDrag: "Arrastra para seleccionar un área",
        hintClick: "Haz clic en una ventana para capturarla",
        folderLabel: "Guardar en",
        folderChoose: "Elegir…",
        editorTitle: "Captura de pantalla",
        textPlaceholder: "Texto",
        cancel: "Cancelar",
        backdropLabel: "Fondo",
        backdropNone: "Ninguno",
        copyButton: "Copiar",
        saveButton: "Guardar",
        saveAsButton: "Guardar como…",
        discardTitle: "¿Descartar esta captura?",
        discardMessage: "Todavía no se copió ni se guardó.",
        copiedHUD: "Captura copiada",
        savedHUDFormat: "Guardada en %@",
        backdropPaddingLabel: "Margen",
        backdropWallpaperLabel: "Fondo de pantalla",
        backdropImageButton: "Imagen…",
        backdropSolidLabel: "Sólido",
        backdropGradientLabel: "Degradado",
        backdropCornersLabel: "Esquinas",
        backdropSavePreset: "Guardar fondo",
        backdropDeletePreset: "Eliminar",
        backdropCustomLabel: "Personalizado",
        openEditorToggle: "Abrir el editor justo después de capturar",
        openEditorCaption: "La captura omite la previsualización flotante y se abre lista para anotar.",
        backdropBlurLabel: "Desenfoque",
        scrollingCaptureHintOff: "S activa desplazamiento",
        scrollingCaptureHintOn: "Desplazamiento activo",
        done: "Listo",
        scrollingCaptureSelectionHint: "Selecciona solo la parte de la página que se desplaza.",
        screenCaptureTitle: "Herramientas de captura"
    )

    static let de = ScreenshotFeatureStrings(
        pageTitle: "Bildschirmfoto",
        hubDescription: "Nimmt einen Bereich, ein Fenster oder den Bildschirm auf und erlaubt Anmerkungen",
        panelCaption: "Einen Bereich, ein Fenster oder den ganzen Bildschirm aufnehmen",
        fileNamePrefix: "Bildschirmfoto",
        hintDrag: "Ziehen, um einen Bereich auszuwählen",
        hintClick: "Auf ein Fenster klicken, um es aufzunehmen",
        folderLabel: "Sichern unter",
        folderChoose: "Auswählen…",
        editorTitle: "Bildschirmfoto",
        textPlaceholder: "Text",
        cancel: "Abbrechen",
        backdropLabel: "Hintergrund",
        backdropNone: "Ohne",
        copyButton: "Kopieren",
        saveButton: "Sichern",
        saveAsButton: "Sichern unter…",
        discardTitle: "Dieses Bildschirmfoto verwerfen?",
        discardMessage: "Es wurde noch nicht kopiert oder gesichert.",
        copiedHUD: "Bildschirmfoto kopiert",
        savedHUDFormat: "Gesichert unter %@",
        backdropPaddingLabel: "Rand",
        backdropWallpaperLabel: "Hintergrundbild",
        backdropImageButton: "Bild…",
        backdropSolidLabel: "Einfarbig",
        backdropGradientLabel: "Verlauf",
        backdropCornersLabel: "Ecken",
        backdropSavePreset: "Hintergrund sichern",
        backdropDeletePreset: "Entfernen",
        backdropCustomLabel: "Eigene",
        openEditorToggle: "Editor direkt nach der Aufnahme öffnen",
        openEditorCaption: "Die Aufnahme überspringt die schwebende Vorschau und öffnet sich bereit für Anmerkungen.",
        backdropBlurLabel: "Unschärfe",
        scrollingCaptureHintOff: "S schaltet Scrollen um",
        scrollingCaptureHintOn: "Scrollen aktiv",
        done: "Fertig",
        scrollingCaptureSelectionHint: "Wähle nur den scrollenden Bereich der Seite aus.",
        screenCaptureTitle: "Bildschirm erfassen"
    )

    static let fr = ScreenshotFeatureStrings(
        pageTitle: "Capture d'écran",
        hubDescription: "Capture une zone, une fenêtre ou l'écran et permet de l'annoter",
        panelCaption: "Capturez une zone, une fenêtre ou tout l'écran",
        fileNamePrefix: "Capture d'écran",
        hintDrag: "Faites glisser pour sélectionner une zone",
        hintClick: "Cliquez sur une fenêtre pour la capturer",
        folderLabel: "Enregistrer dans",
        folderChoose: "Choisir…",
        editorTitle: "Capture d'écran",
        textPlaceholder: "Texte",
        cancel: "Annuler",
        backdropLabel: "Arrière-plan",
        backdropNone: "Aucun",
        copyButton: "Copier",
        saveButton: "Enregistrer",
        saveAsButton: "Enregistrer sous…",
        discardTitle: "Abandonner cette capture ?",
        discardMessage: "Elle n'a pas encore été copiée ni enregistrée.",
        copiedHUD: "Capture copiée",
        savedHUDFormat: "Enregistrée dans %@",
        backdropPaddingLabel: "Marge",
        backdropWallpaperLabel: "Fond d'écran",
        backdropImageButton: "Image…",
        backdropSolidLabel: "Unie",
        backdropGradientLabel: "Dégradé",
        backdropCornersLabel: "Coins",
        backdropSavePreset: "Enregistrer le fond",
        backdropDeletePreset: "Supprimer",
        backdropCustomLabel: "Personnalisé",
        openEditorToggle: "Ouvrir l'éditeur juste après la capture",
        openEditorCaption: "La capture ignore l'aperçu flottant et s'ouvre prête à être annotée.",
        backdropBlurLabel: "Flou",
        scrollingCaptureHintOff: "S active le défilement",
        scrollingCaptureHintOn: "Défilement activé",
        done: "Terminé",
        scrollingCaptureSelectionHint: "Sélectionnez uniquement la partie de la page qui défile.",
        screenCaptureTitle: "Outils de capture"
    )

    static let it = ScreenshotFeatureStrings(
        pageTitle: "Istantanea schermo",
        hubDescription: "Cattura un'area, una finestra o lo schermo e permette di annotarla",
        panelCaption: "Cattura un'area, una finestra o l'intero schermo",
        fileNamePrefix: "Istantanea",
        hintDrag: "Trascina per selezionare un'area",
        hintClick: "Fai clic su una finestra per catturarla",
        folderLabel: "Salva in",
        folderChoose: "Scegli…",
        editorTitle: "Istantanea schermo",
        textPlaceholder: "Testo",
        cancel: "Annulla",
        backdropLabel: "Sfondo",
        backdropNone: "Nessuno",
        copyButton: "Copia",
        saveButton: "Salva",
        saveAsButton: "Salva come…",
        discardTitle: "Eliminare questa istantanea?",
        discardMessage: "Non è stata ancora copiata né salvata.",
        copiedHUD: "Istantanea copiata",
        savedHUDFormat: "Salvata in %@",
        backdropPaddingLabel: "Margine",
        backdropWallpaperLabel: "Sfondo scrivania",
        backdropImageButton: "Immagine…",
        backdropSolidLabel: "Tinta unita",
        backdropGradientLabel: "Gradiente",
        backdropCornersLabel: "Angoli",
        backdropSavePreset: "Salva sfondo",
        backdropDeletePreset: "Rimuovi",
        backdropCustomLabel: "Personalizzato",
        openEditorToggle: "Apri l'editor subito dopo la cattura",
        openEditorCaption: "La cattura salta l'anteprima flottante e si apre pronta per le annotazioni.",
        backdropBlurLabel: "Sfocatura",
        scrollingCaptureHintOff: "S attiva scorrimento",
        scrollingCaptureHintOn: "Scorrimento attivo",
        done: "Fine",
        scrollingCaptureSelectionHint: "Seleziona solo la parte della pagina che scorre.",
        screenCaptureTitle: "Acquisizione schermo"
    )

    static let ja = ScreenshotFeatureStrings(
        pageTitle: "スクリーンショット",
        hubDescription: "範囲やウインドウ、画面全体を撮影して注釈を付けられます",
        panelCaption: "範囲、ウインドウ、画面全体を撮影します",
        fileNamePrefix: "スクリーンショット",
        hintDrag: "ドラッグで範囲を選択",
        hintClick: "ウインドウをクリックで撮影",
        folderLabel: "保存先",
        folderChoose: "選択…",
        editorTitle: "スクリーンショット",
        textPlaceholder: "テキスト",
        cancel: "キャンセル",
        backdropLabel: "背景",
        backdropNone: "なし",
        copyButton: "コピー",
        saveButton: "保存",
        saveAsButton: "別名で保存…",
        discardTitle: "このスクリーンショットを破棄しますか?",
        discardMessage: "まだコピーも保存もされていません。",
        copiedHUD: "スクリーンショットをコピーしました",
        savedHUDFormat: "%@ に保存しました",
        backdropPaddingLabel: "余白",
        backdropWallpaperLabel: "壁紙",
        backdropImageButton: "画像…",
        backdropSolidLabel: "単色",
        backdropGradientLabel: "グラデーション",
        backdropCornersLabel: "角丸",
        backdropSavePreset: "背景を保存",
        backdropDeletePreset: "削除",
        backdropCustomLabel: "カスタム",
        openEditorToggle: "撮影後すぐにエディタを開く",
        openEditorCaption: "撮影はフローティングプレビューを飛ばして、すぐに注釈を付けられる状態で開きます。",
        backdropBlurLabel: "ぼかし",
        scrollingCaptureHintOff: "Sでスクロール切替",
        scrollingCaptureHintOn: "スクロール有効",
        done: "完了",
        scrollingCaptureSelectionHint: "ページ内でスクロールする部分だけを選択してください。",
        screenCaptureTitle: "画面キャプチャ"
    )

    static let ko = ScreenshotFeatureStrings(
        pageTitle: "스크린샷",
        hubDescription: "영역, 윈도우 또는 화면을 캡처하고 주석을 남길 수 있습니다",
        panelCaption: "영역, 윈도우 또는 전체 화면을 캡처합니다",
        fileNamePrefix: "스크린샷",
        hintDrag: "드래그하여 영역 선택",
        hintClick: "윈도우를 클릭하면 캡처됩니다",
        folderLabel: "저장 위치",
        folderChoose: "선택…",
        editorTitle: "스크린샷",
        textPlaceholder: "텍스트",
        cancel: "취소",
        backdropLabel: "배경",
        backdropNone: "없음",
        copyButton: "복사",
        saveButton: "저장",
        saveAsButton: "다른 이름으로 저장…",
        discardTitle: "이 스크린샷을 버리시겠습니까?",
        discardMessage: "아직 복사되거나 저장되지 않았습니다.",
        copiedHUD: "스크린샷이 복사되었습니다",
        savedHUDFormat: "%@에 저장되었습니다",
        backdropPaddingLabel: "여백",
        backdropWallpaperLabel: "배경 화면",
        backdropImageButton: "이미지…",
        backdropSolidLabel: "단색",
        backdropGradientLabel: "그라데이션",
        backdropCornersLabel: "모서리",
        backdropSavePreset: "배경 저장",
        backdropDeletePreset: "제거",
        backdropCustomLabel: "사용자화",
        openEditorToggle: "캡처 후 바로 편집기 열기",
        openEditorCaption: "캡처가 떠 있는 미리보기를 건너뛰고 바로 주석을 남길 수 있는 상태로 열립니다.",
        backdropBlurLabel: "흐림",
        scrollingCaptureHintOff: "S로 스크롤 전환",
        scrollingCaptureHintOn: "스크롤 켜짐",
        done: "완료",
        scrollingCaptureSelectionHint: "페이지에서 스크롤되는 부분만 선택하세요.",
        screenCaptureTitle: "화면 캡처"
    )

    static let zhHans = ScreenshotFeatureStrings(
        pageTitle: "截屏",
        hubDescription: "截取区域、窗口或整个屏幕并添加标注",
        panelCaption: "截取区域、窗口或整个屏幕",
        fileNamePrefix: "截屏",
        hintDrag: "拖动以选择区域",
        hintClick: "点按窗口即可截取",
        folderLabel: "存储位置",
        folderChoose: "选择…",
        editorTitle: "截屏",
        textPlaceholder: "文本",
        cancel: "取消",
        backdropLabel: "背景",
        backdropNone: "无",
        copyButton: "拷贝",
        saveButton: "存储",
        saveAsButton: "存储为…",
        discardTitle: "要丢弃这张截屏吗？",
        discardMessage: "它还没有被拷贝或存储。",
        copiedHUD: "截屏已拷贝",
        savedHUDFormat: "已存储到 %@",
        backdropPaddingLabel: "边距",
        backdropWallpaperLabel: "壁纸",
        backdropImageButton: "图片…",
        backdropSolidLabel: "纯色",
        backdropGradientLabel: "渐变",
        backdropCornersLabel: "圆角",
        backdropSavePreset: "保存背景",
        backdropDeletePreset: "移除",
        backdropCustomLabel: "自定义",
        openEditorToggle: "截取后立即打开编辑器",
        openEditorCaption: "截屏会跳过浮动预览，直接打开即可开始标注。",
        backdropBlurLabel: "模糊",
        scrollingCaptureHintOff: "按 S 切换滚动",
        scrollingCaptureHintOn: "滚动已开启",
        done: "完成",
        scrollingCaptureSelectionHint: "只选择页面中会滚动的部分。",
        screenCaptureTitle: "屏幕捕捉"
    )

    static let zhTW = ScreenshotFeatureStrings(
        pageTitle: "截圖",
        hubDescription: "擷取區域、視窗或整個螢幕並加上標註",
        panelCaption: "擷取區域、視窗或整個螢幕",
        fileNamePrefix: "截圖",
        hintDrag: "拖移以選取區域",
        hintClick: "按一下視窗即可擷取",
        folderLabel: "儲存位置",
        folderChoose: "選擇…",
        editorTitle: "截圖",
        textPlaceholder: "文字",
        cancel: "取消",
        backdropLabel: "背景",
        backdropNone: "無",
        copyButton: "拷貝",
        saveButton: "儲存",
        saveAsButton: "另存為…",
        discardTitle: "要捨棄這張截圖嗎?",
        discardMessage: "它還沒有被拷貝或儲存。",
        copiedHUD: "截圖已拷貝",
        savedHUDFormat: "已儲存到 %@",
        backdropPaddingLabel: "邊距",
        backdropWallpaperLabel: "桌布",
        backdropImageButton: "圖片…",
        backdropSolidLabel: "純色",
        backdropGradientLabel: "漸層",
        backdropCornersLabel: "圓角",
        backdropSavePreset: "儲存背景",
        backdropDeletePreset: "移除",
        backdropCustomLabel: "自訂",
        openEditorToggle: "擷取後立即開啟編輯器",
        openEditorCaption: "截圖會略過浮動預覽，直接開啟即可開始標註。",
        backdropBlurLabel: "模糊",
        scrollingCaptureHintOff: "按 S 切換捲動",
        scrollingCaptureHintOn: "捲動已開啟",
        done: "完成",
        scrollingCaptureSelectionHint: "只選取頁面中會捲動的部分。",
        screenCaptureTitle: "螢幕擷取"
    )

    static let zhHK = ScreenshotFeatureStrings(
        pageTitle: "截圖",
        hubDescription: "擷取範圍、視窗或整個螢幕並加上標註",
        panelCaption: "擷取範圍、視窗或整個螢幕",
        fileNamePrefix: "截圖",
        hintDrag: "拖移以選取範圍",
        hintClick: "按一下視窗即可擷取",
        folderLabel: "儲存位置",
        folderChoose: "選擇…",
        editorTitle: "截圖",
        textPlaceholder: "文字",
        cancel: "取消",
        backdropLabel: "背景",
        backdropNone: "無",
        copyButton: "拷貝",
        saveButton: "儲存",
        saveAsButton: "另存為…",
        discardTitle: "要捨棄這張截圖嗎?",
        discardMessage: "它還未被拷貝或儲存。",
        copiedHUD: "截圖已拷貝",
        savedHUDFormat: "已儲存到 %@",
        backdropPaddingLabel: "邊距",
        backdropWallpaperLabel: "桌布",
        backdropImageButton: "圖片…",
        backdropSolidLabel: "純色",
        backdropGradientLabel: "漸變",
        backdropCornersLabel: "圓角",
        backdropSavePreset: "儲存背景",
        backdropDeletePreset: "移除",
        backdropCustomLabel: "自訂",
        openEditorToggle: "擷取後立即開啟編輯器",
        openEditorCaption: "截圖會略過浮動預覽，直接開啟即可開始標註。",
        backdropBlurLabel: "模糊",
        scrollingCaptureHintOff: "按 S 切換捲動",
        scrollingCaptureHintOn: "捲動已開啟",
        done: "完成",
        scrollingCaptureSelectionHint: "只選取頁面中會捲動嘅部分。",
        screenCaptureTitle: "螢幕擷取"
    )
}
