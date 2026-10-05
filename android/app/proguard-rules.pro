# Keep Bouncy Castle provider registration and Jakarta Mail protocols.
-keep class org.bouncycastle.** { *; }
-keep class jakarta.mail.** { *; }
-keep class com.sun.mail.** { *; }
# Tor native bridge is loaded reflectively.
-keep class org.torproject.** { *; }
