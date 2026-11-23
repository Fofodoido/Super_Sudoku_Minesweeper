module Explosion exposing (styles, view)

{-| Animação da bomba pixel-art explodindo em 3D (inspirada no Zachstronaut
Firebomb), implementada em 100% Elm + CSS puro sem dependências externas de JS.
-}

import Html exposing (Html, div, text)
import Html.Attributes exposing (attribute, class, style)


type alias Pixel =
    { x : Int
    , y : Int
    , color : String
    , dx : Int
    , dy : Int
    , dz : Int
    }


styles : Html msg
styles =
    Html.node "style"
        []
        [ text """
@keyframes ms-shake {
  0%, 100% { transform: translate(0, 0); }
  15% { transform: translate(-8px, -5px) rotate(-1deg); }
  30% { transform: translate(8px, 4px) rotate(1deg); }
  45% { transform: translate(-6px, 5px) rotate(-0.5deg); }
  60% { transform: translate(6px, -4px) rotate(0.5deg); }
  75% { transform: translate(-3px, 2px); }
}
@keyframes ms-flash {
  0% { opacity: 0.85; }
  35% { opacity: 0.15; }
  55% { opacity: 0.6; }
  100% { opacity: 0; }
}
@keyframes ms-pixel-fly {
  0% {
    transform: translate3d(0, 0, 0) rotateX(0deg) rotateY(0deg);
    opacity: 1;
  }
  12% {
    transform: translate3d(0, 0, 0) scale(1.15);
    opacity: 1;
  }
  100% {
    transform: translate3d(var(--dx), var(--dy), var(--dz)) rotateX(540deg) rotateY(720deg);
    opacity: 0;
  }
}
@keyframes ms-cell-boom {
  0% { transform: scale(1); box-shadow: 0 0 0 0 rgba(255, 120, 0, 0.9); }
  40% { transform: scale(1.35); box-shadow: 0 0 24px 8px rgba(255, 60, 0, 0.9); }
  100% { transform: scale(1); box-shadow: 0 0 10px 2px rgba(220, 38, 38, 0.7); }
}
.minesweeper-app--exploded {
  animation: ms-shake 0.45s ease-out;
}
.ms-explosion-overlay {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 9999;
  overflow: hidden;
}
.ms-explosion-flash {
  position: absolute;
  inset: 0;
  background: radial-gradient(circle, rgba(255,234,216,0.95) 0%, rgba(255,102,0,0.5) 45%, transparent 80%);
  animation: ms-flash 0.5s ease-out forwards;
}
.ms-bomb-stage {
  position: fixed;
  left: 50%;
  top: 50%;
  width: 192px;
  height: 192px;
  margin-left: -96px;
  margin-top: -96px;
  perspective: 400px;
}
.ms-bomb-pixel {
  position: absolute;
  width: 12px;
  height: 12px;
  animation: ms-pixel-fly 1.35s cubic-bezier(0.18, 0.75, 0.35, 1) forwards;
}
.board-cell--exploded {
  animation: ms-cell-boom 0.5s ease-out forwards;
}
""" ]


view : Html msg
view =
    div [ class "ms-explosion-overlay", attribute "aria-hidden" "true" ]
        [ div [ class "ms-explosion-flash" ] []
        , div [ class "ms-bomb-stage" ] (List.map viewPixel bombPixels)
        ]


viewPixel : Pixel -> Html msg
viewPixel p =
    div
        [ class "ms-bomb-pixel"
        , style "left" (String.fromInt p.x ++ "px")
        , style "top" (String.fromInt p.y ++ "px")
        , style "background-color" p.color
        , style "--dx" (String.fromInt p.dx ++ "px")
        , style "--dy" (String.fromInt p.dy ++ "px")
        , style "--dz" (String.fromInt p.dz ++ "px")
        ]
        []


bombPixels : List Pixel
bombPixels =
    [ Pixel 24 24 "#ffffff" -449 16 90
    , Pixel 36 24 "#ffffff" -394 -94 -45
    , Pixel 12 36 "#ffffff" -395 29 30
    , Pixel 48 36 "#ffffff" -274 16 25
    , Pixel 72 36 "#949595" -144 -34 -45
    , Pixel 12 48 "#ff0000" -626 84 85
    , Pixel 60 48 "#4a4b4b" -174 103 95
    , Pixel 72 48 "#767777" -118 34 -40
    , Pixel 84 48 "#949595" -53 64 25
    , Pixel 108 48 "#101010" 105 25 -45
    , Pixel 120 48 "#2c2c2c" 199 54 20
    , Pixel 132 48 "#464546" 304 84 85
    , Pixel 144 48 "#505050" 209 113 -100
    , Pixel 24 60 "#ffff00" -477 85 -45
    , Pixel 48 60 "#000000" -347 126 85
    , Pixel 60 60 "#1e1e1e" -133 146 -100
    , Pixel 72 60 "#4a4b4b" -93 98 -35
    , Pixel 84 60 "#000000" -43 119 30
    , Pixel 96 60 "#020202" 16 139 95
    , Pixel 108 60 "#1f1f1f" 86 91 -40
    , Pixel 120 60 "#464646" 166 112 25
    , Pixel 132 60 "#696969" 256 132 90
    , Pixel 144 60 "#797979" 355 85 -45
    , Pixel 156 60 "#696968" 464 105 20
    , Pixel 168 60 "#464645" 583 126 85
    , Pixel 0 72 "#ffff00" -454 164 30
    , Pixel 60 72 "#000000" -227 145 -45
    , Pixel 72 72 "#1e1e1e" -152 156 20
    , Pixel 84 72 "#000000" -68 167 85
    , Pixel 96 72 "#050505" 13 179 -100
    , Pixel 108 72 "#252525" 68 152 -35
    , Pixel 120 72 "#505050" 133 164 30
    , Pixel 132 72 "#797979" 208 175 95
    , Pixel 144 72 "#949595" 292 148 -40
    , Pixel 156 72 "#797879" 387 160 25
    , Pixel 168 72 "#505050" 491 171 90
    , Pixel 24 84 "#ffff00" -309 206 -35
    , Pixel 72 84 "#000000" -127 208 25
    , Pixel 84 84 "#000000" -57 210 90
    , Pixel 96 84 "#020202" 22 205 -45
    , Pixel 108 84 "#1f1f1f" 111 207 20
    , Pixel 120 84 "#464646" 211 209 85
    , Pixel 132 84 "#696969" 160 211 -100
    , Pixel 144 84 "#787979" 229 206 -35
    , Pixel 156 84 "#696968" 309 208 30
    , Pixel 168 84 "#464646" 399 211 95
    , Pixel 180 84 "#000000" 498 205 -40
    , Pixel 72 96 "#000000" -101 253 30
    , Pixel 84 96 "#000000" -46 246 95
    , Pixel 96 96 "#000000" 18 262 -40
    , Pixel 108 96 "#101010" 93 255 25
    , Pixel 120 96 "#2c2c2c" 177 249 90
    , Pixel 132 96 "#464646" 272 264 -45
    , Pixel 144 96 "#505050" 376 258 20
    , Pixel 156 96 "#464646" 490 251 85
    , Pixel 168 96 "#2c2c2c" 307 244 -100
    , Pixel 180 96 "#000000" 391 260 -35
    , Pixel 72 108 "#000000" -161 293 85
    , Pixel 84 108 "#000000" -35 277 -100
    , Pixel 96 108 "#000000" 14 314 -35
    , Pixel 108 108 "#000000" 74 298 30
    , Pixel 120 108 "#101010" 144 282 95
    , Pixel 132 108 "#1f1f1f" 224 319 -40
    , Pixel 144 108 "#252525" 313 303 25
    , Pixel 156 108 "#1f1f1f" 412 287 90
    , Pixel 168 108 "#101010" 522 324 -45
    , Pixel 180 108 "#000000" 640 309 20
    , Pixel 72 120 "#000000" -135 326 90
    , Pixel 84 120 "#000000" -61 384 -45
    , Pixel 96 120 "#000000" 23 359 20
    , Pixel 108 120 "#000000" 117 334 85
    , Pixel 120 120 "#000000" 111 309 -100
    , Pixel 132 120 "#020202" 176 368 -35
    , Pixel 144 120 "#050505" 250 343 30
    , Pixel 156 120 "#020202" 335 318 95
    , Pixel 168 120 "#000000" 429 376 -40
    , Pixel 180 120 "#000000" 534 351 25
    , Pixel 84 132 "#000000" -50 433 -40
    , Pixel 96 132 "#000000" 19 399 25
    , Pixel 108 132 "#000000" 99 365 90
    , Pixel 120 132 "#000000" 188 444 -45
    , Pixel 132 132 "#000000" 288 410 20
    , Pixel 144 132 "#000000" 397 376 85
    , Pixel 156 132 "#000000" 258 342 -100
    , Pixel 168 132 "#000000" 337 422 -35
    , Pixel 84 144 "#000000" -39 476 -35
    , Pixel 96 144 "#000000" 15 432 30
    , Pixel 108 144 "#000000" 80 389 95
    , Pixel 120 144 "#000000" 155 490 -40
    , Pixel 132 144 "#000000" 240 447 25
    , Pixel 144 144 "#000000" 334 403 90
    , Pixel 156 144 "#000000" 438 504 -45
    , Pixel 168 144 "#000000" 552 461 20
    , Pixel 108 156 "#000000" 62 407 -100
    , Pixel 120 156 "#000000" 122 529 -35
    , Pixel 132 156 "#000000" 192 477 30
    , Pixel 144 156 "#000000" 271 425 95
    ]
