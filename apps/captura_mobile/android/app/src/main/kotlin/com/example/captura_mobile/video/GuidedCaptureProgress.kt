package com.example.captura_mobile.video

internal enum class GuidanceProgressState(val label: String) {
    PENDING("Pendiente"), OBSERVING("Observando"), NEEDS_IMPROVEMENT("Mejorar imagen"),
    VISUALLY_SUFFICIENT("Imagen suficiente · solo 2D"), MANUALLY_CONFIRMED("Declarado por vos · no verificado"),
}

/** Only image stabilization and local 2D continuity can advance automatically. */
internal class GuidedCaptureProgress {
    var step = 0
        private set
    var revision = 0
        private set
    var stableFraming = false
        private set
    var visualContinuity = false
        private set
    var referenceCandidate = false
        private set
    var hiddenAreas = 0
        private set
    var manualSteps = 0
        private set
    var unverifiedDeclarations = 0
        private set
    var referenceContinuedManually = false
        private set
    private var referenceCandidateSeen = false
    var state = GuidanceProgressState.PENDING
        private set
    private var wantsReference = true
    private var stableSamples = 0
    private var changedSamples = 0
    private var lastSample = 0
    private var lastChange = 0
    private var lastIssue = VisualIssue.WARMUP
    private var lastMessage: String? = null

    fun reset(firstRoom: Boolean = true, wantsReference: Boolean = true) {
        step = if (firstRoom) 0 else 1
        revision++
        this.wantsReference = wantsReference
        stableFraming = false; visualContinuity = false; referenceCandidate = false
        hiddenAreas = 0; manualSteps = 0; stableSamples = 0; changedSamples = 0
        unverifiedDeclarations = 0; referenceContinuedManually = false; referenceCandidateSeen = false
        lastSample = 0; lastChange = 0; lastIssue = VisualIssue.WARMUP
        lastMessage = null
        state = GuidanceProgressState.PENDING
    }

    fun observe(feedback: VisualFeedback, referenceCandidate: Boolean = false): Int {
        // PixelCopy failures have no sample index. Do not retain the preceding success
        // just because this availability notification is not a new analyzed image.
        if (feedback.samples == 0 && feedback.state == VisualState.NOT_VERIFIABLE) {
            invalidateObservation()
            lastIssue = VisualIssue.WARMUP
            lastMessage = feedback.message
            return step
        }
        // Repeated or stale callbacks cannot accumulate evidence or restore old quality.
        if (feedback.issue == VisualIssue.STALE) {
            invalidateObservation()
            return step
        }
        if (feedback.samples <= lastSample) return step
        lastSample = feedback.samples
        val newChange = feedback.changedComparisons > lastChange
        lastChange = feedback.changedComparisons
        lastIssue = feedback.issue
        lastMessage = feedback.message
        stableFraming = feedback.issue == VisualIssue.NONE && feedback.imageStable == true
        visualContinuity = feedback.issue == VisualIssue.NONE && feedback.localMatching
        this.referenceCandidate = wantsReference && referenceCandidate
        if (this.referenceCandidate) referenceCandidateSeen = true
        state = when {
            feedback.issue == VisualIssue.WARMUP -> GuidanceProgressState.OBSERVING
            feedback.issue != VisualIssue.NONE -> GuidanceProgressState.NEEDS_IMPROVEMENT
            else -> GuidanceProgressState.OBSERVING
        }
        // Stable texture alone does not establish a reference object. Require a current
        // candidate in BOTH qualified samples, not one carried over from an earlier view.
        stableSamples = if (stableFraming && visualContinuity &&
            (!wantsReference || this.referenceCandidate)) stableSamples + 1 else 0
        changedSamples = if (visualContinuity && feedback.imageChanged && newChange) changedSamples + 1 else 0
        // Neither transition establishes object identity, parallax, a corner or a new wall.
        if ((step == 0 && stableSamples >= 2) || (step == 2 && changedSamples >= 2)) {
            step++
            revision++
            stableSamples = 0; changedSamples = 0
            state = GuidanceProgressState.VISUALLY_SUFFICIENT
        } else if (step != 0 && step != 2 && stableFraming && visualContinuity) {
            state = GuidanceProgressState.VISUALLY_SUFFICIENT
        }
        return step
    }

    /** A paused or disabled sampler supplies no current evidence. Preserve human declarations. */
    fun invalidateObservation() {
        stableFraming = false; visualContinuity = false; referenceCandidate = false
        stableSamples = 0; changedSamples = 0; lastIssue = VisualIssue.STALE
        lastMessage = null
        state = GuidanceProgressState.PENDING
        revision++
    }

    fun instruction(): String = when (step) {
        0 -> if (wantsReference && referenceCandidate) "Candidato detectado; mantené el objeto completo y estable."
            else if (wantsReference) "Sin candidato: incluí el objeto completo y su apoyo, o continuá manualmente."
            else "Mantené la cámara estable para comprobar la imagen."
        1 -> "Mostrá una pared y su base; confirmá abajo lo que ves."
        2 -> "Movete suavemente de costado conservando parte de la vista anterior."
        3 -> "Mostrá una esquina y otra pared; confirmá abajo si las ves."
        4 -> "Recorré las demás paredes con vistas compartidas; confirmá lo visto."
        else -> if (hiddenAreas > 0) "Buscá otra posición para las zonas tapadas o usá captura manual."
            else "Volvé al inicio y revisá bases y esquinas tapadas."
    }

    fun confirmation(): String? = when (step) {
        0 -> if (wantsReference) "Seguir sin verificar objeto" else null
        1 -> "Veo la pared y su base"
        3 -> "Veo esquina y pared contigua"
        4 -> "Recorrí las demás paredes"
        else -> null
    }

    /** Human declarations never create visual evidence or verify coverage. */
    fun confirm(expectedRevision: Int): Int {
        if (expectedRevision == revision && confirmation() != null) {
            manualSteps++
            if (!visualContinuity) unverifiedDeclarations++
            if (step == 0) referenceContinuedManually = true
            step++
            revision++
            stableSamples = 0; changedSamples = 0
            state = GuidanceProgressState.MANUALLY_CONFIRMED
        }
        return step
    }

    fun markHidden(expectedRevision: Int = revision) {
        if (expectedRevision != revision) return
        hiddenAreas++
        revision++
    }

    fun qualityWarning(): String? = when {
        lastIssue == VisualIssue.WARMUP && state == GuidanceProgressState.PENDING -> lastMessage
        lastIssue == VisualIssue.LOW_MATCHES -> "Volvé un poco y conservá parte de la vista anterior."
        lastIssue != VisualIssue.NONE && lastIssue != VisualIssue.WARMUP && lastIssue != VisualIssue.STALE -> lastMessage
        hiddenAreas > 0 -> "Muebles o zonas tapadas: cambiá de posición; no damos esa zona por cubierta."
        referenceContinuedManually -> "Referencia no verificada: revisá el objeto y sus medidas reales en el primer MP4."
        unverifiedDeclarations > 0 -> "Hay pasos declarados sin imagen suficiente; revisalos o usá captura manual."
        state == GuidanceProgressState.MANUALLY_CONFIRMED -> "Confirmación personal; cobertura 3D no verificada."
        else -> null
    }

    fun summary(): String = "$manualSteps pasos confirmados por la persona; $hiddenAreas zonas declaradas no visibles. " +
        "$unverifiedDeclarations declaraciones sin imagen suficiente. " +
        "Sin paredes ni esquinas detectadas. Las coincidencias 2D no verifican cobertura. " +
        (if (wantsReference) (when {
            referenceContinuedManually -> "Referencia no verificada; continuación manual. "
            referenceCandidateSeen -> "Candidato observado en vista previa, no confirmado en el MP4. "
            else -> "Sin candidato de referencia observado. "
        }) + "Objeto y dimensiones se revisan en el primer cuadro MP4; confirmarlos no aplica escala al modelo. "
         else "Sin referencia solicitada; escala métrica no disponible. ") +
        "Geometría y escala pendientes de Worker3D. Cobertura 3D pendiente."
}
