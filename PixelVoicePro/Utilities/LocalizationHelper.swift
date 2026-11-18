import Foundation

/// Centraliza toda la localización multi-idioma de Voice Notes mediante `Localizable.xcstrings`,
/// usando inglés como respaldo universal si el idioma del dispositivo no cuenta con traducción directa.
enum L10n {
    static func tr(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: fallback, comment: "")
    }

    static func fmt(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
        let format = tr(key, fallback)
        return String(format: format, locale: Locale.current, arguments: args)
    }

    // MARK: - General / Acciones Comunes

    static var cancel: String { tr("action.cancel", "Cancel") }
    static var save: String { tr("action.save", "Save") }
    static var done: String { tr("action.done", "Done") }
    static var close: String { tr("action.close", "Close") }
    static var delete: String { tr("action.delete", "Delete") }
    static var remove: String { tr("action.remove", "Remove") }
    static var favorite: String { tr("action.favorite", "Favorite") }
    static var tags: String { tr("action.tags", "Tags") }
    static var export: String { tr("action.export", "Export") }
    static var mark: String { tr("action.mark", "Mark") }
    static var jump: String { tr("action.jump", "Jump") }
    static var settingsTitle: String { tr("settings.title", "Settings") }

    // MARK: - Dashboard y Carpetas

    static var searchPrompt: String { tr("search.prompt", "Search in Voice Notes...") }
    static var searchAccessibility: String { tr("search.accessibility", "Search in Voice Notes") }
    static var searchCloseAccessibility: String { tr("search.close.accessibility", "Close search") }
    static var foldersManageTitle: String { tr("folders.manage.title", "Folders") }
    static var foldersManageSubtitle: String { tr("folders.manage.subtitle", "Create or hide") }
    static var foldersManageAccessibility: String { tr("folders.manage.accessibility", "Manage, create, or hide folders") }
    static var folderAll: String { tr("folder.all", "All") }
    static var folderFavorites: String { tr("folder.favorites", "Favorites") }

    static func folderRecordingCount(_ count: Int) -> String {
        if count == 1 {
            return tr("folder.count.singular", "1 recording")
        }
        return fmt("folder.count.plural", "%@ recordings", "\(count)")
    }

    static func folderEmptyTitle(_ folderTitle: String) -> String {
        fmt("folder.empty.title", "No recordings in %@", folderTitle)
    }
    static var folderEmptySubtitle: String {
        tr("folder.empty.subtitle", "Tap the red button below to record directly in this folder.")
    }
    static func groupNotesCount(_ count: Int) -> String {
        fmt("group.notes.count", "%@ note(s)", "\(count)")
    }

    static func searchExactMatches(_ count: Int) -> String {
        fmt("search.exact_matches", "Exact Matches (%@)", "\(count)")
    }
    static var searchTapToJump: String { tr("search.tap_to_jump", "Tap to jump to timestamp") }
    static func searchNoResults(_ query: String) -> String {
        fmt("search.no_results", "No results found for \"%@\" in any recording.", query)
    }
    static func searchMinuteBadge(_ timestamp: String) -> String {
        fmt("search.minute_badge", "At %@", timestamp)
    }
    static func searchMatchingNotes(_ count: Int) -> String {
        fmt("search.matching_notes", "Matching Notes (%@)", "\(count)")
    }

    static func processingBanner(_ title: String) -> String {
        fmt("processing.banner", "Processing %@", title)
    }
    static var processingShort: String { tr("processing.short", "Analyzing...") }
    static var processingBackgroundShort: String { tr("processing.background_short", "Processing in background...") }
    static var newRecordingAccessibility: String { tr("record.new.accessibility", "New Recording") }
    static var quickEditAccessibility: String { tr("action.quick_edit.accessibility", "Rename and tag note") }
    static var renameAndTags: String { tr("action.rename_and_tags", "Rename & Tags") }
    static var exportMenuAction: String { tr("action.export.menu", "Export (Audio / PDF / MD / TXT)") }
    static var deleteRecordingAction: String { tr("action.delete_recording", "Delete Recording") }

    // MARK: - Cabina de Grabación y Onda

    static var boothTitlePlaceholder: String { tr("booth.title_placeholder", "Note title (optional)...") }
    static var boothHideLiveTranscript: String { tr("booth.hide_live_transcript", "Hide live transcript (Save battery)") }
    static var boothShowLiveTranscript: String { tr("booth.show_live_transcript", "Show live transcript") }
    static func boothListening(_ languageName: String) -> String {
        fmt("booth.listening", "Listening (%@)...", languageName)
    }
    static var boothLiveHint: String {
        tr("booth.live_hint", "Words will appear here live. You can hide this panel anytime to save battery during a long session.")
    }
    static var boothBookmarkPlaceholder: String { tr("booth.bookmark_placeholder", "Optional note for bookmark...") }
    static func boothBookmarkSaved(_ timestamp: String) -> String {
        fmt("booth.bookmark_saved", "Bookmark saved at %@", timestamp)
    }
    static var boothBookmarkButton: String { tr("booth.bookmark_button", "Bookmark") }
    static var boothPause: String { tr("booth.pause", "Pause") }
    static var boothResume: String { tr("booth.resume", "Resume") }
    static var boothFinishSave: String { tr("booth.finish_save", "Finish & Save") }

    static var waveformFollowing: String { tr("waveform.following", "Following") }
    static var waveformFollow: String { tr("waveform.follow", "Follow") }
    static var waveformWave: String { tr("waveform.wave", "Wave") }
    static var waveformFFT: String { tr("waveform.fft", "FFT") }

    // MARK: - Vista de Detalle y Reproducción

    static var tabAudio: String { tr("tab.audio", "Audio") }
    static var tabTranscript: String { tr("tab.transcript", "Transcript") }
    static var tabSummary: String { tr("tab.summary", "Summary") }
    static var tabDetails: String { tr("tab.details", "Details") }
    static var toolbarSpeakers: String { tr("toolbar.speakers", "Speakers") }
    static var detailSearchPlaceholder: String { tr("detail.search_placeholder", "Search word in this recording...") }
    static var detailTranscribingBg: String { tr("detail.transcribing_bg", "Transcribing audio in background...") }
    static var detailNoTranscript: String { tr("detail.no_transcript", "This recording contains no transcribed words.") }
    static var detailBookmarks: String { tr("detail.bookmarks", "Bookmarks") }
    static func detailAddBookmarkAt(_ timestamp: String) -> String {
        fmt("detail.add_bookmark_at", "Add bookmark at %@...", timestamp)
    }
    static var detailNoBookmarks: String {
        tr("detail.no_bookmarks", "No bookmarks in this note. You can add them live while recording or here during playback.")
    }
    static var detailAcousticEvents: String { tr("detail.acoustic_events", "Acoustic Events") }
    static var detailNoAcousticEvents: String {
        tr("detail.no_acoustic_events", "No non-verbal events (laughter, applause, music, or long pauses) were detected in this recording.")
    }
    static func detailAIConfidenceDuration(confidencePct: Int, durationText: String) -> String {
        fmt("detail.ai_confidence_duration", "AI Confidence: %1$@%% · Duration: %2$@s", "\(confidencePct)", durationText)
    }
    static var detailSpeakerParticipation: String { tr("detail.speaker_participation", "Speaker Participation") }
    static var detailRenameSpeakers: String { tr("detail.rename_speakers", "Rename Speakers") }
    static func detailWordsDuration(wordCount: Int, durationText: String) -> String {
        fmt("detail.words_duration", "%1$@ words · %2$@", "\(wordCount)", durationText)
    }
    static func detailMeanPitch(_ hz: Int) -> String {
        fmt("detail.mean_pitch", "Mean fundamental frequency (Pitch F0): %@ Hz", "\(hz)")
    }

    static var detailSectionTimeline: String { tr("detail.section.timeline", "Timeline") }
    static var detailExactCreated: String { tr("detail.exact_created", "Exact Created") }
    static var detailExactEnded: String { tr("detail.exact_ended", "Exact Ended") }
    static var detailGroupDate: String { tr("detail.group_date", "Group Date") }
    static var detailDayPeriod: String { tr("detail.day_period", "Time of Day") }
    static var detailDurationPrecise: String { tr("detail.duration_precise", "Duration (Centiseconds)") }
    static var detailSectionStorage: String { tr("detail.section.storage", "Storage") }
    static var detailFileName: String { tr("detail.file_name", "File Name") }
    static var detailFormatCodec: String { tr("detail.format_codec", "Format & Codec") }
    static var detailExactSize: String { tr("detail.exact_size", "Exact Size") }
    static var detailSampleRate: String { tr("detail.sample_rate", "Sample Rate") }
    static var detailBitrate: String { tr("detail.bitrate", "Bitrate") }
    static var detailChannels: String { tr("detail.channels", "Channels") }
    static func detailChannelsMono(_ count: Int) -> String {
        fmt("detail.channels_mono_value", "%@ (Mono Voice)", "\(count)")
    }
    static var detailSHA256: String { tr("detail.sha256", "SHA-256 Integrity") }
    static var detailCalculating: String { tr("detail.calculating", "Calculating...") }
    static var detailSectionAI: String { tr("detail.section.ai", "Analysis & AI") }
    static var detailEngineUsed: String { tr("detail.engine_used", "Engine Used") }
    static var detailDetectedSpeakers: String { tr("detail.detected_speakers", "Detected Speakers") }
    static var detailSilenceIntervals: String { tr("detail.silence_intervals", "Silence Intervals") }
    static var detailSectionExport: String { tr("detail.section.export", "Export") }
    static var detailExportButton: String { tr("detail.export_button", "Export Audio / Document") }

    static var playerSkippingSilence: String { tr("player.skipping_silence", "Skipping silence!") }
    static func playerSavedSeconds(_ secondsText: String) -> String {
        fmt("player.saved_seconds", "Saved: %@s", secondsText)
    }
    static var playerSkipSilences: String { tr("player.skip_silences", "Skip silences") }

    // MARK: - Ajustes y Modales

    static var settingsSectionStorage: String { tr("settings.section.storage", "Storage & Library") }
    static var settingsSavedNotes: String { tr("settings.saved_notes", "Saved voice notes") }
    static var settingsTotalStorage: String { tr("settings.total_storage", "Total storage used") }
    static var settingsSectionAudio: String { tr("settings.section.audio", "AVFoundation Audio Engine") }
    static var settingsRecordingFormat: String { tr("settings.recording_format", "Recording Format") }
    static var settingsSampleRate: String { tr("settings.sample_rate", "Sample Rate") }
    static var settingsSectionSpeechHeader: String { tr("settings.section.speech_header", "Real-Time Transcription (Speech Framework)") }
    static var settingsSectionSpeechFooter: String {
        tr("settings.section.speech_footer", "On-Device mode processes speech directly on the iPhone's Neural Engine with zero latency and complete privacy.")
    }
    static var settingsSpeechLanguage: String { tr("settings.speech_language", "Transcription Language") }
    static var settingsSpeechAuto: String { tr("settings.speech_auto", "Automatic (iPhone Language)") }
    static var settingsSpeechActiveLabel: String { tr("settings.speech_active_label", "Active recognition") }
    static var settingsSpeechOnDevice: String { tr("settings.speech_on_device", "Prioritize On-Device Recognition (Offline)") }
    static var settingsSpeechOfflineAvailable: String { tr("settings.speech_offline_available", "On-Device Ready") }
    static var settingsSpeechCloudFallback: String { tr("settings.speech_cloud_fallback", "Network Assisted") }
    static var settingsSectionWhisperHeader: String { tr("settings.section.whisper_header", "Whisper AI Hybrid Module (Optional)") }
    static var settingsSectionWhisperFooter: String {
        tr("settings.section.whisper_footer", "You can connect the official OpenAI Whisper API or a local Whisper server on your network to refine word-by-word timestamps after each recording.")
    }
    static var settingsWhisperToggle: String { tr("settings.whisper_toggle", "Enable Whisper API / Local Post-Processing") }
    static var settingsWhisperEndpoint: String { tr("settings.whisper_endpoint", "Endpoint URL") }
    static var settingsWhisperModel: String { tr("settings.whisper_model", "Model (e.g. whisper-1 or whisper-large-v3)") }
    static var settingsWhisperAPIKey: String { tr("settings.whisper_apikey", "API Key (Bearer Token)") }
    static var settingsSectionDates: String { tr("settings.section.dates", "Exact Date & Time Format") }
    static var settingsDateStandard: String { tr("settings.date_standard", "Active standard") }
    static var settingsDateExample: String { tr("settings.date_example", "Live example") }

    static var tagsSectionDefault: String { tr("tags.section.default", "Default Folders") }
    static var tagsSectionDefaultFooter: String {
        tr("tags.section.default_footer", "Default folders can be hidden from the home screen using the eye icon, but cannot be deleted.")
    }
    static var tagsSectionCustom: String { tr("tags.section.custom", "Custom Tags") }
    static var tagsEmptyCustom: String { tr("tags.empty_custom", "You haven't created any custom tags yet.") }
    static var tagsSectionNew: String { tr("tags.section.new", "New Tag") }
    static var tagsNewPlaceholder: String { tr("tags.new_placeholder", "Name (e.g. Anatomy, Project)") }
    static var tagsCreateButton: String { tr("tags.create_button", "Create Tag") }
    static var tagsTitle: String { tr("tags.title", "Folders & Tags") }
    static var tagsClearFilter: String { tr("tags.clear_filter", "Clear filter") }
    static var tagsHiddenBadge: String { tr("tags.hidden_badge", "Hidden") }
    static func tagsShowAccessibility(_ name: String) -> String { fmt("tags.show_accessibility", "Show tag %@", name) }
    static func tagsHideAccessibility(_ name: String) -> String { fmt("tags.hide_accessibility", "Hide tag %@", name) }
    static func tagsDeleteAccessibility(_ name: String) -> String { fmt("tags.delete_accessibility", "Delete tag %@", name) }

    static var quickCustomTitleHeader: String { tr("quick.custom_title_header", "CUSTOM NOTE TITLE") }
    static var quickTitlePlaceholder: String { tr("quick.title_placeholder", "e.g. Distributed Systems Lecture...") }
    static func quickDurationLabel(_ value: String) -> String { fmt("quick.duration_label", "Duration: %@", value) }
    static func quickSizeLabel(_ value: String) -> String { fmt("quick.size_label", "Size: %@", value) }
    static var quickManageTagsAccessibility: String { tr("quick.manage_tags_accessibility", "Add or manage tags") }
    static var quickNavTitle: String { tr("quick.nav_title", "Title & Tags") }

    static var speakersInstructions: String {
        tr("speakers.instructions", "Replace \"Speaker 1\", \"Speaker 2\", etc. with each person's real name. The name and color will instantly update across all transcript paragraphs, statistics, and exports.")
    }
    static func speakersPitchWords(hz: Int, words: Int) -> String {
        fmt("speakers.pitch_words", "Mean vocal pitch: %1$@ Hz · %2$@ words", "\(hz)", "\(words)")
    }
    static var speakersNamePlaceholder: String { tr("speakers.name_placeholder", "Real name (e.g. Dr. Martin, Anna, Professor)") }
    static var speakersSelectedBadge: String { tr("speakers.selected_badge", "• Selected") }
    static var speakersNavTitle: String { tr("speakers.nav_title", "Speaker Identification") }
    static var speakersApplyButton: String { tr("speakers.apply_button", "Apply to Entire Note") }

    static var exportSummaryHeader: String { tr("export.summary_header", "Recording Summary to Export") }
    static func exportSummaryLine(duration: String, size: String, speakersCount: Int) -> String {
        fmt("export.summary_line", "Duration: %1$@ · Size: %2$@ · %3$@ speaker(s)", duration, size, "\(speakersCount)")
    }
    static var exportFormatHeader: String { tr("export.format_header", "Select Export Format") }
    static var exportPreviewHeader: String { tr("export.preview_header", "Generated Document Preview") }
    static var exportNavTitle: String { tr("export.nav_title", "Export & Share") }
    static var exportShareNow: String { tr("export.share_now", "Share Now") }
    static func exportError(_ message: String) -> String {
        fmt("export.error", "Could not generate export package: %@", message)
    }

    // MARK: - Modelos, Eventos, Formatos y Servicios

    static var formatM4AName: String { tr("format.m4a.name", "High-Fidelity AAC (.m4a)") }
    static var formatWAVName: String { tr("format.wav.name", "Lossless Linear PCM (.wav)") }
    static var formatM4ADesc: String {
        tr("format.m4a.desc", "Smart high-clarity vocal compression (~1.1 MB/min). Ideal for long lectures, interviews, and daily use.")
    }
    static var formatWAVDesc: String {
        tr("format.wav.desc", "Uncompressed studio audio (~5.5 MB/min). Maximum dynamic range for deep acoustic analysis.")
    }
    static var rate44100: String { tr("rate.44100", "44.1 kHz (CD Standard)") }
    static var rate48000: String { tr("rate.48000", "48.0 kHz (Pro Studio)") }

    static func localizedPredefinedTagName(id: String, fallback: String) -> String {
        switch id {
        case "tag_universidad": return tr("tag.universidad", "University")
        case "tag_clases": return tr("tag.clases", "Classes")
        case "tag_entrevistas": return tr("tag.entrevistas", "Interviews")
        case "tag_trabajo": return tr("tag.trabajo", "Work")
        case "tag_ideas": return tr("tag.ideas", "Ideas")
        case "tag_reunion": return tr("tag.reunion", "Meetings")
        case "tag_microbiologia": return tr("tag.microbiologia", "Microbiology")
        case "tag_anatomia_humana": return tr("tag.anatomia_humana", "Human Anatomy")
        case "tag_investigacion_social": return tr("tag.investigacion_social", "Social Research")
        default: return fallback
        }
    }
    static var tagCustomDefault: String { tr("tag.custom_default", "Custom") }

    static func speakerDefaultName(_ number: Int) -> String {
        fmt("speaker.default_name", "Speaker %@", "\(number)")
    }
    static func speakerShortBadge(_ number: Int) -> String {
        fmt("speaker.short_badge", "S%@", "\(number)")
    }

    static var eventLaughter: String { tr("event.laughter", "Laughter") }
    static var eventApplause: String { tr("event.applause", "Applause") }
    static var eventMusic: String { tr("event.music", "Music") }
    static var eventSigh: String { tr("event.sigh", "Sigh") }
    static var eventLongPause: String { tr("event.long_pause", "Long Pause") }
    static var eventCough: String { tr("event.cough", "Cough / Throat Clear") }
    static func eventDetected(emoji: String, title: String, confidencePct: Int) -> String {
        fmt("event.detected", "%1$@ %2$@ detected (%3$@%%)", emoji, title, "\(confidencePct)")
    }

    static var periodMorning: String { tr("period.morning", "Morning") }
    static var periodAfternoon: String { tr("period.afternoon", "Afternoon") }
    static var periodNight: String { tr("period.night", "Night") }

    static var unitBytes: String { tr("unit.bytes", "bytes") }
    static func recordingDefaultTitle(_ number: Int) -> String {
        fmt("recording.default_title", "Recording %@", "\(number)")
    }
    static var recordingTitlePrefixCheck: String {
        tr("recording.title_prefix_check", "Recording ")
    }
    static func recordingDateFallback(_ exactDate: String) -> String {
        fmt("recording.date_fallback", "Recording from %@", exactDate)
    }
    static func bookmarkDefaultNumbered(_ number: Int) -> String {
        fmt("bookmark.default_numbered", "Bookmark %@", "\(number)")
    }
    static func bookmarkAtTimestamp(_ timestamp: String) -> String {
        fmt("bookmark.at_timestamp", "Bookmark at %@", timestamp)
    }
    static func bookmarkKeyMoment(index: Int, speakerBadge: String) -> String {
        fmt("bookmark.key_moment", "Key moment #%1$@ (%2$@)", "\(index)", speakerBadge)
    }
    static var bookmarkFromLockScreen: String {
        tr("bookmark.from_lockscreen", "Bookmark from Lock Screen")
    }
    static func searchEventConfidence(_ pct: Int) -> String {
        fmt("search.event_confidence", "Acoustic event detected with %@%% confidence", "\(pct)")
    }

    static var micDefault: String { tr("mic.default", "iPhone Microphone") }
    static var micBuiltIn: String { tr("mic.builtin", "iPhone Built-in Microphone") }
    static var recorderPreparing: String { tr("recorder.preparing", "Preparing analysis...") }
    static var recorderReady: String { tr("recorder.ready", "Ready to record") }
    static var recorderLiveOn: String { tr("recorder.live_on", "🎙️ Live transcription enabled") }
    static var recorderPowerSaverActive: String { tr("recorder.power_saver_active", "⚡ Power Saver Active (Lightweight audio)") }
    static func recorderPowerSaverBadge(_ badge: String) -> String {
        fmt("recorder.power_saver_badge", "⚡ Power Saver (%@)", badge)
    }
    static var recorderPowerSaverShort: String { tr("recorder.power_saver_short", "⚡ Saver") }
    static var recorderMicPermissionError: String {
        tr("recorder.mic_permission_error", "Microphone permission is required to record voice notes.")
    }
    static var recorderPaused: String { tr("recorder.paused", "⏸️ Recording paused") }
    static var recorderResumed: String { tr("recorder.resumed", "🎙️ Recording resumed") }
    static func recorderBookmarkAt(_ timestamp: String) -> String {
        fmt("recorder.bookmark_at", "🔖 Bookmark at %@", timestamp)
    }
    static var recorderProcessingBg: String {
        tr("recorder.processing_bg", "Processing analysis & AI in background...")
    }

    static var bgPreparing: String { tr("bg.preparing", "Preparing background analysis...") }
    static var bgAnalyzingSpeakers: String { tr("bg.analyzing_speakers", "Analyzing speakers...") }
    static var bgDetectingEvents: String { tr("bg.detecting_events", "Detecting acoustic events and pauses...") }
    static var bgVerifyingSHA: String { tr("bg.verifying_sha", "Verifying SHA-256 integrity...") }

    static var speechSplitting45s: String {
        tr("speech.splitting_45s", "Splitting audio into safe 45s chunks for full transcription...")
    }
    static func speechTranscribingChunk(current: Int, total: Int, startTime: String) -> String {
        fmt("speech.transcribing_chunk", "Transcribing chunk %1$@ of %2$@ (%3$@)...", "\(current)", "\(total)", startTime)
    }
    static var speechAligning: String {
        tr("speech.aligning", "Aligning speakers, punctuation, and acoustic events...")
    }
    static var speechCompleted: String { tr("speech.completed", "Processing completed!") }
    static func speechEngineApple(_ localeId: String, onDevice: Bool) -> String {
        if onDevice {
            return fmt("speech.engine_apple_ondevice", "Apple Speech On-Device (%@) + PixelVoice 45s Pipeline", localeId)
        }
        return fmt("speech.engine_apple", "Apple Speech (%@) + PixelVoice 45s Pipeline", localeId)
    }

    static var lockscreenRecordingTitle: String { tr("lockscreen.recording_title", "Recording Voice Note") }
    static var lockscreenInProgress: String { tr("lockscreen.in_progress", "Recording in Progress") }
    static var lockscreenStatusPaused: String { tr("lockscreen.status_paused", "⏸️ PAUSED") }
    static var lockscreenStatusLive: String { tr("lockscreen.status_live", "🔴 RECORDING LIVE") }
    static var lockscreenAddBookmark: String { tr("lockscreen.add_bookmark", "Add Bookmark") }
    static var lockscreenBadgePaused: String { tr("lockscreen.badge_paused", "PAUSED") }
    static func lockscreenBadgeLive(_ badge: String) -> String { fmt("lockscreen.badge_live", "LIVE · %@", badge) }

    // MARK: - Exportación

    static var exportFormatAudioTitle: String { tr("export.format.audio.title", "Audio File Only") }
    static var exportFormatAudioSub: String {
        tr("export.format.audio.sub", "Exports the original audio file (.m4a or .wav) dated to the exact second.")
    }
    static var exportFormatPDFTitle: String { tr("export.format.pdf.title", "PDF Transcript (.pdf)") }
    static var exportFormatPDFSub: String {
        tr("export.format.pdf.sub", "Formatted PDF document with exact time, color-coded speakers, bookmarks, and event tags.")
    }
    static var exportFormatMDTitle: String { tr("export.format.md.title", "Markdown Transcript (.md)") }
    static var exportFormatMDSub: String {
        tr("export.format.md.sub", "Structured .md file with metadata tables, speaker blocks, and acoustic events.")
    }
    static var exportFormatTXTTitle: String { tr("export.format.txt.title", "Plain Text Transcript (.txt)") }
    static var exportFormatTXTSub: String {
        tr("export.format.txt.sub", "Universal .txt file with second-accurate timestamps, speakers, and events.")
    }
    static var exportFormatPkgTitle: String { tr("export.format.pkg.title", "Complete Package (Audio + PDF + MD + TXT)") }
    static var exportFormatPkgSub: String {
        tr("export.format.pkg.sub", "Includes original audio along with PDF, Markdown (.md), and Text (.txt) transcripts ready for Google NotebookLM.")
    }
    static var exportPackagePrefix: String { tr("export.package_prefix", "Package") }
    static var exportFileFallback: String { tr("export.file_fallback", "VoiceNotes_Recording") }

    static var exportMDSubtitle: String { tr("export.md.subtitle", "> Generated by **Voice Notes** · Smart Recorder & Transcription") }
    static var exportMDMetadataHeading: String { tr("export.md.metadata_heading", "## 📋 Exact File Metadata") }
    static var exportMDTableHeader: String { tr("export.md.table_header", "| Property | Exact Value |") }
    static var exportMDPropCreated: String { tr("export.md.prop.created", "Created Date & Time") }
    static var exportMDPropEnded: String { tr("export.md.prop.ended", "Ended Date & Time") }
    static var exportMDPropPeriod: String { tr("export.md.prop.period", "Time of Day") }
    static var exportMDPropDuration: String { tr("export.md.prop.duration", "Exact Duration") }
    static var exportMDPropSize: String { tr("export.md.prop.size", "File Size") }
    static var exportMDPropFormat: String { tr("export.md.prop.format", "Format & Quality") }
    static var exportMDPropTags: String { tr("export.md.prop.tags", "Tags") }
    static var exportMDSpeakersHeading: String { tr("export.md.speakers_heading", "## 🗣️ Identified Speakers (Speaker Diarization)") }
    static func exportMDSpeakerLine(displayName: String, defaultLabel: String, duration: String, words: Int, pitchHz: Int) -> String {
        fmt("export.md.speaker_line", "- **%1$@** (`%2$@`): %3$@ spoken · %4$@ words · Mean pitch %5$@ Hz", displayName, defaultLabel, duration, "\(words)", "\(pitchHz)")
    }
    static var exportMDBookmarksHeading: String { tr("export.md.bookmarks_heading", "## 🔖 Live Time Bookmarks") }
    static func exportMDBookmarkCreated(_ exactDate: String) -> String {
        fmt("export.md.bookmark_created", "Created: %@", exactDate)
    }
    static var exportMDTranscriptHeading: String { tr("export.md.transcript_heading", "## 📝 Full Transcript & Acoustic Events") }
    static var exportMDEventsHeading: String { tr("export.md.events_heading", "## 🔊 Detected Acoustic Events Summary (SoundAnalysis)") }
    static func exportMDEventLine(tag: String, confidencePct: Int, durationText: String) -> String {
        fmt("export.md.event_line", "- `%1$@` — Confidence: %2$@%% (Duration: %3$@s)", tag, "\(confidencePct)", durationText)
    }

    static var exportTXTHeader: String { tr("export.txt.header", "VOICE NOTES - TRANSCRIPTION & ACOUSTIC REPORT") }
    static var exportTXTTitle: String { tr("export.txt.title", "TITLE") }
    static var exportTXTCreated: String { tr("export.txt.created", "EXACT DATE & TIME") }
    static var exportTXTEnded: String { tr("export.txt.ended", "EXACT END TIME") }
    static var exportTXTPeriod: String { tr("export.txt.period", "TIME OF DAY") }
    static var exportTXTDuration: String { tr("export.txt.duration", "EXACT DURATION") }
    static var exportTXTSize: String { tr("export.txt.size", "FILE SIZE") }
    static var exportTXTFormat: String { tr("export.txt.format", "AUDIO FORMAT") }
    static var exportTXTTags: String { tr("export.txt.tags", "TAGS") }
    static var exportTXTSpeakersHeader: String { tr("export.txt.speakers_header", "IDENTIFIED SPEAKERS:") }
    static func exportTXTSpeakerLine(displayName: String, defaultLabel: String, words: Int, duration: String) -> String {
        fmt("export.txt.speaker_line", "  • %1$@ (%2$@) - %3$@ words (%4$@)", displayName, defaultLabel, "\(words)", duration)
    }
    static var exportTXTBookmarksHeader: String { tr("export.txt.bookmarks_header", "TIME BOOKMARKS:") }
    static var exportTXTTranscriptHeader: String { tr("export.txt.transcript_header", "SYNCHRONIZED TRANSCRIPT:") }

    static var exportPDFHeader: String { tr("export.pdf.header", "VOICE NOTES · TRANSCRIPTION & ACOUSTIC AI REPORT") }
    static func exportPDFDatetime(date: String, period: String) -> String {
        fmt("export.pdf.datetime", "Exact Date & Time: %1$@ (%2$@)", date, period)
    }
    static func exportPDFMetrics(duration: String, size: String, formatBadge: String) -> String {
        fmt("export.pdf.metrics", "Duration: %1$@   |   Size: %2$@   |   Format: %3$@", duration, size, formatBadge)
    }
    static func exportPDFSpeakers(_ summary: String) -> String {
        fmt("export.pdf.speakers", "Detected speakers: %@", summary)
    }
    static func exportPDFSpeakerItem(displayName: String, words: Int, duration: String) -> String {
        fmt("export.pdf.speaker_item", "%1$@ (%2$@ words · %3$@)", displayName, "\(words)", duration)
    }
    static var exportPDFBookmarks: String { tr("export.pdf.bookmarks", "Live Bookmarks:") }
    static var exportPDFTranscript: String { tr("export.pdf.transcript", "Synchronized Transcript & Acoustic Events:") }

    // MARK: - Grabaciones de Demostración Iniciales

    static var sample1Title: String { tr("sample1.title", "Lecture: Neural Networks & CoreML Audio") }
    static var sample1Speaker1: String { tr("sample1.speaker1", "Dr. Alex Vega") }
    static var sample1Speaker2: String { tr("sample1.speaker2", "Sophia (Student)") }
    static var sample1Turn1: String {
        tr("sample1.turn1", "Welcome to the artificial intelligence lab applied to real-time acoustic processing.")
    }
    static var sample1Turn2: String {
        tr("sample1.turn2", "Professor, can the model separate voices and detect laughter during an interview?")
    }
    static var sample1Turn3: String {
        tr("sample1.turn3", "Exactly, we combine SoundAnalysis with spectral diarization to index every second with absolute precision.")
    }
    static var sample1BM1Label: String { tr("sample1.bm1.label", "Sophia's question on Diarization") }
    static var sample1BM1Note: String { tr("sample1.bm1.note", "Included on Friday's midterm exam") }
    static var sample1BM2Label: String { tr("sample1.bm2.label", "CoreML architecture explanation") }
    static var sample1BM2Note: String { tr("sample1.bm2.note", "Review spectrogram diagram") }

    static var sample2Title: String { tr("sample2.title", "UX Interview: Instant Search Flow") }
    static var sample2Turn1: String {
        tr("sample2.turn1", "We need global search to find any keyword across all recordings.")
    }
    static var sample2Turn2: String {
        tr("sample2.turn2", "Totally agree, and tapping the word should jump to the exact second of the audio.")
    }
    static var sample2BM1Label: String { tr("sample2.bm1.label", "Interactive Karaoke requirement") }
    static var sample2BM1Note: String { tr("sample2.bm1.note", "60 FPS synchronization") }

    static var sample3Title: String { tr("sample3.title", "Architecture Ideas: AAC Compression & Metadata") }
    static var sample3Speaker1: String { tr("sample3.speaker1", "Lead Engineer") }
    static var sample3Turn1: String {
        tr("sample3.turn1", "Important reminder: all cards must show day, month, year, and exact time to the second with AM or PM.")
    }
    static var sample3BM1Label: String { tr("sample3.bm1.label", "Top priority: Exact timestamps") }
    static var sample3BM1Note: String { tr("sample3.bm1.note", "Never use ambiguous relative dates") }

    // MARK: - IA Adaptativa, SpeechAnalyzer y Sensibilidad Acústica

    static var settingsSectionAcousticHeader: String { tr("settings.section.acoustic_header", "Acoustic Event Sensitivity") }
    static var settingsSectionAcousticFooter: String {
        tr("settings.section.acoustic_footer", "Adjust how easily laughter, sighs, coughs, and long pauses are detected. Higher sensitivity captures softer reactions and lets you re-scan existing notes.")
    }
    static var settingsAcousticSensitivity: String { tr("settings.acoustic_sensitivity", "Detection Sensitivity") }
    static var acousticSensitivityConservative: String { tr("acoustic.sensitivity.conservative", "Conservative (Standard)") }
    static var acousticSensitivityBalanced: String { tr("acoustic.sensitivity.balanced", "Balanced (Recommended)") }
    static var acousticSensitivityHigh: String { tr("acoustic.sensitivity.high", "High (Laughs & Sighs)") }
    static var settingsSpeechModernEngine: String { tr("settings.speech_modern_engine", "Use Modern Apple SpeechAnalyzer (iOS 26+)") }
    static var settingsSpeechModernEngineReady: String { tr("settings.speech_modern_engine_ready", "Supported on this iPhone for full-audio transcription") }
    static var settingsSpeechModernEngineFallback: String { tr("settings.speech_modern_engine_fallback", "Using classic 45s Speech engine on this iOS version") }

    static var settingsSectionAIHeader: String { tr("settings.section.ai_header", "Adaptive Intelligence (On-Device & Cloud)") }
    static var settingsSectionAIFooter: String {
        tr("settings.section.ai_footer", "On iPhone 15 Pro, 16, and 17 Pro Max, Apple Intelligence runs locally offline for free. On older devices like iPhone 11 Pro Max, the local switch stays disabled and you can configure a free online model (such as Groq) or local Wi-Fi server.")
    }
    static var settingsAILocalToggle: String { tr("settings.ai_local_toggle", "On-Device Apple Intelligence") }
    static var settingsAILocalAvailable: String { tr("settings.ai_local_available", "Ready offline (Apple Intelligence)") }
    static var settingsAILocalDeviceIneligible: String { tr("settings.ai_local_device_ineligible", "Disabled — Requires iPhone 15 Pro / 16 / 17 Pro Max or iPad M1+") }
    static var settingsAILocalDisabledInSystem: String { tr("settings.ai_local_disabled_in_system", "Turn on Apple Intelligence in iOS Settings to enable") }
    static var settingsAILocalDownloading: String { tr("settings.ai_local_downloading", "Apple Intelligence model is preparing on device...") }
    static var settingsAILocalOlderOS: String { tr("settings.ai_local_older_os", "Requires iOS 26 or later with Apple Intelligence hardware") }
    static var settingsAIAutoRefineToggle: String { tr("settings.ai_auto_refine_toggle", "Auto-summarize & polish after recording") }
    static var settingsAIProviderPicker: String { tr("settings.ai_provider_picker", "Refinement Engine") }
    static var aiProviderAutomatic: String { tr("ai.provider.automatic", "Automatic (Local first, then Cloud)") }
    static var aiProviderAppleLocal: String { tr("ai.provider.apple_local", "Apple Intelligence (On-Device)") }
    static var aiProviderCloud: String { tr("ai.provider.cloud", "Online AI (Groq / OpenAI)") }
    static var settingsGroqPresetButton: String { tr("settings.groq_preset_button", "Configure Free Groq Preset (Whisper + Llama)") }
    static var settingsGroqPresetApplied: String { tr("settings.groq_preset_applied", "Groq endpoints applied! Enter your free Groq API key below.") }
    static var settingsAIChatHeader: String { tr("settings.ai_chat_header", "Online AI Text Refinement (Free Tier / Custom)") }
    static var settingsAIChatFooter: String {
        tr("settings.ai_chat_footer", "Optional for older iPhones or cloud summaries. Leave the key empty to reuse the same key from the Whisper section above (ideal for Groq).")
    }
    static var settingsAIChatEndpoint: String { tr("settings.ai_chat_endpoint", "Chat Endpoint URL") }
    static var settingsAIChatModel: String { tr("settings.ai_chat_model", "Chat Model (e.g. llama-3.3-70b-versatile)") }
    static var settingsAIChatAPIKey: String { tr("settings.ai_chat_apikey", "AI Chat API Key (Optional if reusing Whisper)") }

    static var toolbarRefineAI: String { tr("toolbar.refine_ai", "AI Refine") }
    static var aiRefineTitle: String { tr("ai.refine.title", "AI Post-Processing") }
    static var aiSummarySectionTitle: String { tr("ai.summary.section_title", "AI Summary & Key Points") }
    static var aiSummaryEmptyHint: String {
        tr("ai.summary.empty_hint", "No AI summary yet. Tap \"AI Refine\" to polish punctuation or generate a structured summary.")
    }
    static var aiRefineDeviceCapabilities: String { tr("ai.refine.device_capabilities", "Device AI Capabilities") }
    static var aiRefineActionReprocessTitle: String { tr("ai.refine.reprocess_title", "Re-analyze Audio + Laughs & Sighs") }
    static func aiRefineActionReprocessSub(_ engineName: String) -> String {
        fmt("ai.refine.reprocess_sub", "Re-transcribes saved audio using %@ and re-scans laughter, sighs, and pauses at current sensitivity.", engineName)
    }
    static var aiRefineActionFixTextTitle: String { tr("ai.refine.fix_text_title", "Polish Punctuation & Clarity") }
    static func aiRefineActionFixTextSub(_ engineName: String) -> String {
        fmt("ai.refine.fix_text_sub", "Refines spelling, capitalization, and context using %@ while keeping word timestamps synced.", engineName)
    }
    static var aiRefineActionSummaryTitle: String { tr("ai.refine.summary_title", "Generate Summary & Key Takeaways") }
    static func aiRefineActionSummarySub(_ engineName: String) -> String {
        fmt("ai.refine.summary_sub", "Creates concise bullet points and action items using %@.", engineName)
    }
    static var aiRefineActionFullTitle: String { tr("ai.refine.full_title", "Polish Text + Generate Summary") }
    static var aiRefineNeedsCloudOrLocal: String {
        tr("ai.refine.needs_cloud_or_local", "Local Apple Intelligence is not supported on this device. Add a free Groq API key in Settings to use cloud refinement.")
    }
    static var aiRefineOpenSettingsHint: String {
        tr("ai.refine.open_settings_hint", "Configure an API key in Settings (or use a device with Apple Intelligence).")
    }
    static var aiRefineRunningReprocess: String { tr("ai.refine.running_reprocess", "Re-analyzing full audio & acoustic events...") }
    static var aiRefineRunningFixText: String { tr("ai.refine.running_fix_text", "Polishing transcript with AI...") }
    static var aiRefineRunningSummary: String { tr("ai.refine.running_summary", "Generating AI summary...") }
    static var aiRefineCompleted: String { tr("ai.refine.completed", "Update completed!") }
    static var aiEngineAppleIntelligence: String { tr("ai.engine.apple_intelligence", "Apple Intelligence (On-Device)") }
    static func aiEngineCloudLabel(_ model: String) -> String {
        fmt("ai.engine.cloud_label", "Cloud AI (%@)", model)
    }
    static func speechEngineSpeechAnalyzer(_ localeId: String) -> String {
        fmt("speech.engine_speechanalyzer", "Apple SpeechAnalyzer On-Device (%@)", localeId)
    }
    static var exportSummarySectionTitle: String { tr("export.summary_section_title", "AI Summary & Key Takeaways") }
    static var aiErrorNoTranscript: String { tr("ai.error.no_transcript", "This recording has no transcribed words yet. Re-analyze the audio first.") }
    static var aiErrorMissingConfig: String { tr("ai.error.missing_config", "No local Apple Intelligence or Cloud AI key is configured. Add a free Groq API key in Settings.") }
    static var aiErrorLocalHardware: String { tr("ai.error.local_hardware", "Apple Intelligence on-device is not supported on this hardware. Choose Automatic or Online AI in Settings.") }

    // MARK: - Apariencia y Temas

    static var settingsSectionAppearance: String { tr("settings.section.appearance", "Appearance & Theme") }
    static var settingsThemeRowTitle: String { tr("settings.theme.row_title", "App Theme") }
    static var settingsThemeRowSubtitle: String { tr("settings.theme.row_subtitle", "Preserves Light & Dark mode") }
    static var themePickerNavTitle: String { tr("theme.picker.nav_title", "Appearance & Theme") }
    static var themePickerPreviewHeader: String { tr("theme.picker.preview_header", "Live Preview") }
    static var themePickerPreviewClockSample: String { tr("theme.picker.preview_clock_sample", "09:45:12 AM") }
    static var themePickerListHeader: String { tr("theme.picker.list_header", "Available Palettes") }
    static var themePickerFooter: String {
        tr("theme.picker.footer", "Subtle themes update Liquid Glass folders and key accents while keeping system Light/Dark backgrounds, green iPhone switches, speaker colors, and time-of-day badges.")
    }

    static var themeOriginalTitle: String { tr("theme.original.title", "Original") }
    static var themeOriginalSubtitle: String { tr("theme.original.subtitle", "Classic multicolor folders") }
    static var themeBlueTitle: String { tr("theme.blue.title", "Blue") }
    static var themeBlueSubtitle: String { tr("theme.blue.subtitle", "Sapphire, sky & cobalt tones") }
    static var themeRoseTitle: String { tr("theme.rose.title", "Rose") }
    static var themeRoseSubtitle: String { tr("theme.rose.subtitle", "Pastel blush, coral & raspberry") }
    static var themePurpleTitle: String { tr("theme.purple.title", "Purple") }
    static var themePurpleSubtitle: String { tr("theme.purple.subtitle", "Lavender, amethyst & plum") }
    static var themeGreenTitle: String { tr("theme.green.title", "Green") }
    static var themeGreenSubtitle: String { tr("theme.green.subtitle", "Mint, sage & soft emerald") }
    static var themeAmberTitle: String { tr("theme.amber.title", "Amber Gold") }
    static var themeAmberSubtitle: String { tr("theme.amber.subtitle", "Honey, champagne & warm gold") }
    static var themeOrangeTitle: String { tr("theme.orange.title", "Orange") }
    static var themeOrangeSubtitle: String { tr("theme.orange.subtitle", "Peach, tangerine & terracotta") }
    static var themeCherryTitle: String { tr("theme.cherry.title", "Cherry Red") }
    static var themeCherrySubtitle: String { tr("theme.cherry.subtitle", "Cherry, soft ruby & warm garnet") }

    // MARK: - Papelera (Eliminadas recientemente)

    static var trashHomeTitle: String { tr("trash.home.title", "Recently Deleted") }
    static var trashHomeSubtitle: String { tr("trash.home.subtitle", "Removed permanently after 30 days") }
    static var trashNavTitle: String { tr("trash.nav.title", "Recently Deleted") }
    static func trashInfoBanner(count: Int, size: String, days: Int) -> String {
        fmt("trash.info_banner", "%1$@ recording(s) · %2$@ recoverable. Notes are permanently removed after %3$@ days.", "\(count)", size, "\(days)")
    }
    static func trashDaysLeft(_ days: Int) -> String {
        if days <= 0 {
            return tr("trash.expires_today", "Expires today")
        }
        if days == 1 {
            return tr("trash.days_left.singular", "1 day left")
        }
        return fmt("trash.days_left.plural", "%@ days left", "\(days)")
    }
    static var trashRestoreAction: String { tr("trash.action.restore", "Restore") }
    static var trashRestoreAllAction: String { tr("trash.action.restore_all", "Restore All") }
    static var trashDeleteForeverAction: String { tr("trash.action.delete_forever", "Delete Permanently") }
    static var trashEmptyAction: String { tr("trash.action.empty", "Empty Trash") }
    static var trashEmptyTitle: String { tr("trash.empty.title", "Trash is Empty") }
    static var trashEmptySubtitle: String {
        tr("trash.empty.subtitle", "Deleted recordings are kept here for 30 days so you can restore them anytime.")
    }
    static func trashConfirmDeleteTitle(_ title: String) -> String {
        fmt("trash.confirm.delete_title", "Delete \"%@\" permanently?", title)
    }
    static var trashConfirmDeleteMessage: String {
        tr("trash.confirm.delete_message", "This audio file and its transcript will be permanently deleted and cannot be recovered.")
    }
    static func trashConfirmEmptyTitle(count: Int, size: String) -> String {
        fmt("trash.confirm.empty_title", "Permanently delete %1$@ recording(s) (%2$@)?", "\(count)", size)
    }
    static func trashConfirmRestoreAllTitle(count: Int) -> String {
        fmt("trash.confirm.restore_all_title", "Restore all %@ recording(s)?", "\(count)")
    }
    static var trashRestoreAllMessage: String {
        tr("trash.confirm.restore_all_message", "All notes will return to All and their original folders.")
    }

    // MARK: - Estados de Transcripción, Recuperación y Aislamiento de Voz

    static var transcriptionBadgeTooShort: String {
        tr("transcription.badge.too_short", "Short audio (< 3s)")
    }
    static var transcriptionBadgeInterrupted: String {
        tr("transcription.badge.interrupted", "Interrupted — Retry")
    }
    static var transcriptionBadgeFailed: String {
        tr("transcription.badge.failed", "Transcription failed")
    }
    static var transcriptionBadgeNoSpeech: String {
        tr("transcription.badge.no_speech", "No clear speech detected")
    }
    static var transcriptionErrorInterrupted: String {
        tr("transcription.error.interrupted", "Transcription was interrupted by the system. Tap Retry to finish processing from saved audio.")
    }
    static var transcriptionErrorSessionRecovered: String {
        tr("transcription.error.recovered", "Recording recovered automatically after an unexpected interruption. Tap Retry to transcribe.")
    }
    static var transcriptionErrorUnavailable: String {
        tr("transcription.error.unavailable", "Speech recognition service is currently unavailable.")
    }
    static var transcriptionErrorReadFile: String {
        tr("transcription.error.read_file", "Could not read the saved audio file.")
    }
    static var bgTranscriptionKeepOpen: String {
        tr("bg.keep_open", "Transcribing (Keep app open)")
    }
    static var transcriptionRetryButton: String {
        tr("transcription.action.retry", "Retry Transcription")
    }
    static var transcriptionRetryShortForce: String {
        tr("transcription.action.retry_short", "Transcribe Anyway")
    }
    static var transcriptionStateNoSpeechDetail: String {
        tr("transcription.detail.no_speech", "No clear speech detected (music, background noise, or silence only).")
    }
    static var transcriptionStateTooShortDetail: String {
        tr("transcription.detail.too_short", "Recording is under 3 seconds, so automatic transcription was skipped.")
    }
    static var transcriptionStateFailedDetail: String {
        tr("transcription.detail.failed", "Speech recognition failed or lost connectivity before finishing.")
    }
    static var playerVoiceIsolation: String {
        tr("player.voice_isolation", "Voice Isolation")
    }

    // MARK: - Helper de unión de palabras (soporte CJK/sin espacios)

    /// Une tokens de transcripción respetando idiomas sin espacios entre palabras (chino, japonés, tailandés)
    /// mientras conserva espacios normales en idiomas occidentales, cirílico, coreano y árabe.
    static func smartJoinWords(_ words: [String]) -> String {
        guard !words.isEmpty else { return "" }
        var result = ""
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if result.isEmpty {
                result = trimmed
                continue
            }
            if let last = result.unicodeScalars.last, let first = trimmed.unicodeScalars.first,
               isNoSpaceScriptOrPunctuation(last) && isNoSpaceScriptOrPunctuation(first) {
                result += trimmed
            } else if let first = trimmed.unicodeScalars.first, isClosingPunctuation(first) {
                result += trimmed
            } else {
                result += " " + trimmed
            }
        }
        return result
    }

    /// Divide una frase de demostración en palabras/tokens de manera segura incluso en chino o japonés sin espacios.
    static func tokenizeSampleSentence(_ text: String) -> [String] {
        let spaceTokens = text.split(separator: " ").map(String.init)
        if spaceTokens.count > 1 {
            return spaceTokens
        }
        var tokens: [String] = []
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let tagger = text as NSString
        var cursor = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { substring, range, _, _ in
            if let sub = substring, !sub.isEmpty {
                let r = NSRange(range, in: text)
                if r.location > cursor {
                    let gap = tagger.substring(with: NSRange(location: cursor, length: r.location - cursor)).trimmingCharacters(in: .whitespaces)
                    if !gap.isEmpty, let last = tokens.last {
                        tokens[tokens.count - 1] = last + gap
                    }
                }
                tokens.append(sub)
                cursor = r.location + r.length
            }
        }
        if cursor < nsRange.length {
            let trailing = tagger.substring(with: NSRange(location: cursor, length: nsRange.length - cursor)).trimmingCharacters(in: .whitespaces)
            if !trailing.isEmpty, !tokens.isEmpty {
                tokens[tokens.count - 1] += trailing
            }
        }
        return tokens.isEmpty ? spaceTokens : tokens
    }

    private static func isNoSpaceScriptOrPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) || // CJK Unified Ideographs
               (0x3400...0x4DBF).contains(v) || // CJK Extension A
               (0x3040...0x309F).contains(v) || // Hiragana
               (0x30A0...0x30FF).contains(v) || // Katakana
               (0x3000...0x303F).contains(v) || // CJK Symbols & Punctuation
               (0xFF00...0xFFEF).contains(v) || // Fullwidth forms
               (0x0E00...0x0E7F).contains(v)    // Thai
    }

    private static func isClosingPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let chars: Set<Unicode.Scalar> = [".", ",", "!", "?", ";", ":", "。", "，", "、", "！", "？", "；", "：", "…", ")", "]", "」", "』"]
        return chars.contains(scalar)
    }
}
