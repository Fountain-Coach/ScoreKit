% sampler_marks — key/time/clef changes mid-score
\version "2.24.0"
\paper { ragged-right = ##t }
{ \clef treble \key c \major \time 4/4
  c'4 \key d \major d'4 \time 3/4 e'4 \clef bass f,4
}

