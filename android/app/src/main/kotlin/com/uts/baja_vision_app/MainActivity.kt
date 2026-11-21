package com.uts.baja_vision_app

import android.media.AudioManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Los botones de volumen controlan directamente el volumen multimedia,
        // que es el canal por el que sale la sintesis de voz. Asi el usuario
        // sube o baja la voz de la aplicacion sin entrar en ningun menu.
        volumeControlStream = AudioManager.STREAM_MUSIC
    }
}
