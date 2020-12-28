class MoshLocalScrollback < Formula
  desc "Remote terminal application (with local scrollback)"
  homepage "https://mosh.org"
  url "https://mosh.org/mosh-1.3.2.tar.gz"
  sha256 "da600573dfa827d88ce114e0fed30210689381bbdcff543c931e4d6a2e851216"
  revision 11

  head do
    url "https://github.com/mobile-shell/mosh.git", :shallow => false

    depends_on "autoconf" => :build
    depends_on "automake" => :build
  end

  depends_on "pkg-config" => :build
  depends_on "tmux" => :build
  depends_on "protobuf"

  uses_from_macos "ncurses"

  # patch :DATA
  patch do
    url "https://github.com/mobile-shell/mosh/compare/master...rledisez:localScrollback-1.3.2.patch"
    sha256 "95fee840c11aa3d9233c31792602ca7d790bab6400d6ba8901542b428a245c41"
  end

  # Fix mojave build.
  unless build.head?
    patch do
      url "https://github.com/mobile-shell/mosh/commit/e5f8a826ef9ff5da4cfce3bb8151f9526ec19db0.patch?full_index=1"
      sha256 "022bf82de1179b2ceb7dc6ae7b922961dfacd52fbccc30472c527cb7c87c96f0"
    end
  end


  def install
    ENV.cxx11

    # teach mosh to locate mosh-client without referring
    # PATH to support launching outside shell e.g. via launcher
    inreplace "scripts/mosh.pl", "'mosh-client", "\'#{bin}/mosh-client"

    system "./autogen.sh" if build.head?
    system "./configure", "--prefix=#{prefix}", "--enable-completion"
    # system "make", "check"
    system "make", "install"
  end

  test do
    system bin/"mosh-client", "-c"
  end
end

# From here:
# https://github.com/mobile-shell/mosh/compare/master...rledisez:localScrollback-1.3.2?diff=unified
# and
# https://donnlee.com/2018/03/31/mosh-with-iterm2s-tmux-integration/
__END__
diff --git a/src/frontend/mosh-server.cc b/src/frontend/mosh-server.cc
index b90738f2..8d7ee3cc 100644
--- a/src/frontend/mosh-server.cc
+++ b/src/frontend/mosh-server.cc
@@ -92,10 +92,16 @@

 #include "networktransport-impl.h"

-typedef Network::Transport< Terminal::Complete, Network::UserStream > ServerConnection;
+#ifndef __clang__
+/* centos 6 / gcc4.4 hack */
+#undef PRIu64
+#define PRIu64 "lu"
+#endif
+
+typedef Network::Transport< Network::UserStream, Network::UserStream > ServerConnection;

 static void serve( int host_fd,
-		   Terminal::Complete &terminal,
+		   Network::UserStream &terminal,
 		   ServerConnection &network,
 		   long network_timeout,
 		   long network_signaled_timeout );
@@ -407,8 +413,7 @@ static int run_server( const char *desired_ip, const char *desired_port,
     window_size.ws_row = 24;
   }

-  /* open parser and terminal */
-  Terminal::Complete terminal( window_size.ws_col, window_size.ws_row );
+  Network::UserStream terminal;

   /* open network */
   Network::UserStream blank;
@@ -553,7 +558,7 @@ static int run_server( const char *desired_ip, const char *desired_port,

     chdir_homedir();

-    if ( with_motd && (!motd_hushed()) ) {
+    if ( 0 && with_motd && (!motd_hushed()) ) {
       // On illumos motd is printed by /etc/profile.
 #ifndef __sun
       // For Ubuntu, try and print one of {,/var}/run/motd.dynamic.
@@ -628,7 +633,7 @@ static int run_server( const char *desired_ip, const char *desired_port,
   return 0;
 }

-static void serve( int host_fd, Terminal::Complete &terminal, ServerConnection &network, long network_timeout, long network_signaled_timeout )
+static void serve( int host_fd, Network::UserStream &terminal, ServerConnection &network, long network_timeout, long network_signaled_timeout )
 {
   /* scale timeouts */
   const uint64_t network_timeout_ms = static_cast<uint64_t>( network_timeout ) * 1000;
@@ -657,7 +662,6 @@ static void serve( int host_fd, Terminal::Complete &terminal, ServerConnection &
       uint64_t now = Network::timestamp();

       timeout = min( timeout, network.wait_time() );
-      timeout = min( timeout, terminal.wait_time( now ) );
       if ( (!network.get_remote_state_num())
 	   || network.shutdown_in_progress() ) {
         timeout = min( timeout, 5000 );
@@ -706,7 +710,8 @@ static void serve( int host_fd, Terminal::Complete &terminal, ServerConnection &
 	if ( network.get_remote_state_num() != last_remote_num ) {
 	  last_remote_num = network.get_remote_state_num();

-
+	  string terminal_to_host;
+
 	  Network::UserStream us;
 	  us.apply_string( network.get_remote_diff() );
 	  /* apply userstream to terminal */
@@ -731,20 +736,17 @@ static void serve( int host_fd, Terminal::Complete &terminal, ServerConnection &
 		perror( "ioctl TIOCSWINSZ" );
 		network.start_shutdown();
 	      }
-	    }
-	    terminal_to_host += terminal.act( action );
+            } else {
+	      assert(typeid( *action ) == typeid( Parser::UserByte ));
+	      terminal_to_host += ((Parser::UserByte *)action)->c;
+            }
 	  }

-	  if ( !us.empty() ) {
-	    /* register input frame number for future echo ack */
-	    terminal.register_input_frame( last_remote_num, now );
+	  /* write any writeback octets back to the host */
+	  if ( swrite( host_fd, terminal_to_host.c_str(), terminal_to_host.length() ) < 0 ) {
+	    break;
 	  }

-	  /* update client with new state of terminal */
-	  if ( !network.shutdown_in_progress() ) {
-	    network.set_current_state( terminal );
-	  }
-
 	  #ifdef HAVE_UTEMPTER
 	  /* update utmp entry if we have become "connected" */
 	  if ( (!connected_utmp)
@@ -796,10 +798,8 @@ static void serve( int host_fd, Terminal::Complete &terminal, ServerConnection &
         if ( bytes_read <= 0 ) {
 	  network.start_shutdown();
 	} else {
-	  terminal_to_host += terminal.act( string( buf, bytes_read ) );
-
-	  /* update client with new state of terminal */
-	  network.set_current_state( terminal );
+	  for (int i = 0; i < bytes_read; i++)
+            network.get_current_state().push_back( Parser::UserByte( buf[i] ) );
 	}
       }

@@ -831,7 +831,17 @@ static void serve( int host_fd, Terminal::Complete &terminal, ServerConnection &
 	  break;
 	}
       }
-
+
+      //if ( sel.error( network_fd ) ) {
+      //  /* network problem */
+      //  break;
+      //}
+
+      //if ( (!network.shutdown_in_progress()) && sel.error( host_fd ) ) {
+      //  /* host problem */
+      //  network.start_shutdown();
+      //}
+
       /* quit if our shutdown has been acknowledged */
       if ( network.shutdown_in_progress() && network.shutdown_acknowledged() ) {
 	break;
@@ -862,13 +872,6 @@ static void serve( int host_fd, Terminal::Complete &terminal, ServerConnection &
       }
       #endif

-      if ( terminal.set_echo_ack( now ) ) {
-	/* update client with new echo ack */
-	if ( !network.shutdown_in_progress() ) {
-	  network.set_current_state( terminal );
-	}
-      }
-
       if ( !network.get_remote_state_num()
            && time_since_remote_state >= timeout_if_no_client ) {
         fprintf( stderr, "No connection within %llu seconds.\n",
diff --git a/src/frontend/stmclient.cc b/src/frontend/stmclient.cc
index 8523f9c0..4ce98738 100644
--- a/src/frontend/stmclient.cc
+++ b/src/frontend/stmclient.cc
@@ -114,13 +114,9 @@ void STMClient::init( void )
       exit( 1 );
   }

-  /* Put terminal in application-cursor-key mode */
-  swrite( STDOUT_FILENO, display.open().c_str() );
+  /* Do NOT put terminal in application-cursor-key mode */

-  /* Add our name to window title */
-  if ( !getenv( "MOSH_TITLE_NOPREFIX" ) ) {
-    overlays.set_title_prefix( wstring( L"[mosh] " ) );
-  }
+  /* Do NOT add our name to window title */

   /* Set terminal escape key. */
   const char *escape_key_env;
@@ -200,7 +196,6 @@ void STMClient::shutdown( void )
   overlays.get_notification_engine().set_notification_string( wstring( L"" ) );
   overlays.get_notification_engine().server_heard( timestamp() );
   overlays.set_title_prefix( wstring( L"" ) );
-  output_new_frame();

   /* Restore terminal and terminal-driver state */
   swrite( STDOUT_FILENO, display.close().c_str() );
@@ -237,25 +232,16 @@ void STMClient::main_init( void )
     return;
   }

-  /* local state */
-  local_framebuffer = Terminal::Framebuffer( window_size.ws_col, window_size.ws_row );
-  new_state = Terminal::Framebuffer( 1, 1 );
-
-  /* initialize screen */
-  string init = display.new_frame( false, local_framebuffer, local_framebuffer );
-  swrite( STDOUT_FILENO, init.data(), init.size() );
+  /* do NOT initialize screen */

   /* open network */
   Network::UserStream blank;
-  Terminal::Complete local_terminal( window_size.ws_col, window_size.ws_row );
-  network = new Network::Transport< Network::UserStream, Terminal::Complete >( blank, local_terminal,
+  Network::UserStream remote_blank;
+  network = new Network::Transport< Network::UserStream, Network::UserStream >( blank, remote_blank,
 									       key.c_str(), ip.c_str(), port.c_str() );

   network->set_send_delay( 1 ); /* minimal delay on outgoing keystrokes */

-  /* tell server the size of the terminal */
-  network->get_current_state().push_back( Parser::Resize( window_size.ws_col, window_size.ws_row ) );
-
   /* be noisy as necessary */
   network->set_verbose( verbose );
   Select::set_verbose( verbose );
@@ -263,25 +249,23 @@ void STMClient::main_init( void )

 void STMClient::output_new_frame( void )
 {
+  static uint64_t last_remote_num = network->get_remote_state_num();
   if ( !network ) { /* clean shutdown even when not initialized */
     return;
   }
+  if ( network->get_remote_state_num() != last_remote_num ) {
+    last_remote_num = network->get_remote_state_num();

-  /* fetch target state */
-  new_state = network->get_latest_remote_state().state.get_fb();
-
-  /* apply local overlays */
-  overlays.apply( new_state );
+    string terminal_to_host;

-  /* calculate minimal difference from where we are */
-  const string diff( display.new_frame( !repaint_requested,
-					local_framebuffer,
-					new_state ) );
-  swrite( STDOUT_FILENO, diff.data(), diff.size() );
-
-  repaint_requested = false;
-
-  local_framebuffer = new_state;
+    Network::UserStream us;
+    us.apply_string( network->get_remote_diff() );
+    for ( size_t i = 0; i < us.size(); i++ ) {
+            const Parser::Action *action = us.get_action( i );
+            terminal_to_host += ((Parser::UserByte *)action)->c;
+    }
+    swrite( 1, terminal_to_host.c_str(), terminal_to_host.length() );
+  }
 }

 void STMClient::process_network_input( void )
@@ -294,7 +278,6 @@ void STMClient::process_network_input( void )

   overlays.get_prediction_engine().set_local_frame_acked( network->get_sent_state_acked() );
   overlays.get_prediction_engine().set_send_interval( network->send_interval() );
-  overlays.get_prediction_engine().set_local_frame_late_acked( network->get_latest_remote_state().state.get_echo_ack() );
 }

 bool STMClient::process_user_input( int fd )
@@ -317,8 +300,6 @@ bool STMClient::process_user_input( int fd )
     for ( int i = 0; i < bytes_read; i++ ) {
       char the_byte = buf[ i ];

-      overlays.get_prediction_engine().new_user_byte( the_byte, local_framebuffer );
-
       if ( quit_sequence_started ) {
 	if ( the_byte == '.' ) { /* Quit sequence is Ctrl-^ . */
 	  if ( network->has_remote_addr() && (!network->shutdown_in_progress()) ) {
@@ -373,7 +354,7 @@ bool STMClient::process_user_input( int fd )

       lf_entered = ( (the_byte == 0x0A) || (the_byte == 0x0D) ); /* LineFeed, Ctrl-J, '\n' or CarriageReturn, Ctrl-M, '\r' */

-      if ( the_byte == 0x0C ) { /* Ctrl-L */
+      if ( 0 && the_byte == 0x0C ) { /* Ctrl-L */
 	repaint_requested = true;
       }

diff --git a/src/frontend/stmclient.h b/src/frontend/stmclient.h
index 7703bbbc..79f4b3dd 100644
--- a/src/frontend/stmclient.h
+++ b/src/frontend/stmclient.h
@@ -58,9 +58,8 @@ class STMClient {

   struct winsize window_size;

-  Terminal::Framebuffer local_framebuffer, new_state;
   Overlay::OverlayManager overlays;
-  Network::Transport< Network::UserStream, Terminal::Complete > *network;
+  Network::Transport< Network::UserStream, Network::UserStream > *network;
   Terminal::Display display;

   std::wstring connecting_notification;
@@ -91,8 +90,6 @@ class STMClient {
     escape_requires_lf( false ), escape_key_help( L"?" ),
       saved_termios(), raw_termios(),
       window_size(),
-      local_framebuffer( 1, 1 ),
-      new_state( 1, 1 ),
       overlays(),
       network( NULL ),
       display( true ), /* use TERM environment var to initialize display */
@@ -103,20 +100,7 @@ class STMClient {
       clean_shutdown( false ),
       verbose( s_verbose )
   {
-    if ( predict_mode ) {
-      if ( !strcmp( predict_mode, "always" ) ) {
-	overlays.get_prediction_engine().set_display_preference( Overlay::PredictionEngine::Always );
-      } else if ( !strcmp( predict_mode, "never" ) ) {
 	overlays.get_prediction_engine().set_display_preference( Overlay::PredictionEngine::Never );
-      } else if ( !strcmp( predict_mode, "adaptive" ) ) {
-	overlays.get_prediction_engine().set_display_preference( Overlay::PredictionEngine::Adaptive );
-      } else if ( !strcmp( predict_mode, "experimental" ) ) {
-	overlays.get_prediction_engine().set_display_preference( Overlay::PredictionEngine::Experimental );
-      } else {
-	fprintf( stderr, "Unknown prediction mode %s.\n", predict_mode );
-	exit( 1 );
-      }
-    }
   }

   void init( void );
diff --git a/src/network/transportsender-impl.h b/src/network/transportsender-impl.h
index e9e4b6d4..8476fa08 100644
--- a/src/network/transportsender-impl.h
+++ b/src/network/transportsender-impl.h
@@ -62,7 +62,7 @@ TransportSender<MyState>::TransportSender( Connection *s_connection, MyState &in
     shutdown_start( -1 ),
     ack_num( 0 ),
     pending_data_ack( false ),
-    SEND_MINDELAY( 8 ),
+    SEND_MINDELAY( 1 ),
     last_heard( 0 ),
     prng(),
     mindelay_clock( -1 )
@@ -80,7 +80,7 @@ unsigned int TransportSender<MyState>::send_interval( void ) const
     SEND_INTERVAL = SEND_INTERVAL_MAX;
   }

-  return SEND_INTERVAL;
+  return 1;//SEND_INTERVAL;
 }

 /* Housekeeping routine to calculate next send and ack times */
@@ -170,7 +170,8 @@ void TransportSender<MyState>::tick( void )

   string diff = current_state.diff_from( assumed_receiver_state->state );

-  attempt_prospective_resend_optimization( diff );
+  /* todo investigate whether it matters */
+/*  attempt_prospective_resend_optimization( diff );*/

   if ( verbose ) {
     /* verify diff has round-trip identity (modulo Unicode fallback rendering) */
diff --git a/src/statesync/user.cc b/src/statesync/user.cc
index 77dab8e6..f2cdf816 100644
--- a/src/statesync/user.cc
+++ b/src/statesync/user.cc
@@ -78,7 +78,7 @@ string UserStream::diff_from( const UserStream &existing ) const
       {
 	char the_byte = my_it->userbyte.c;
 	/* can we combine this with a previous Keystroke? */
-	if ( (output.instruction_size() > 0)
+	if ( 0 && (output.instruction_size() > 0)
 	     && (output.instruction( output.instruction_size() - 1 ).HasExtension( keystroke )) ) {
 	  output.mutable_instruction( output.instruction_size() - 1 )->MutableExtension( keystroke )->mutable_keys()->append( string( &the_byte, 1 ) );
 	} else {
diff --git a/src/util/pty_compat.cc b/src/util/pty_compat.cc
index c7233264..61033764 100644
--- a/src/util/pty_compat.cc
+++ b/src/util/pty_compat.cc
@@ -92,7 +92,7 @@ pid_t my_forkpty( int *amaster, char *name,
     return -1;
   }

-#ifndef _AIX
+#if 0 //ndef _AIX
   if ( ioctl(slave, I_PUSH, "ptem") < 0 ||
        ioctl(slave, I_PUSH, "ldterm") < 0 ) {
     perror( "ioctl(I_PUSH)" );
@@ -108,13 +108,14 @@ pid_t my_forkpty( int *amaster, char *name,
   if ( name != NULL)
     strcpy( name, slave_name );

-  if ( termp != NULL ) {
+  if ( 0 && termp != NULL ) {
     if ( tcsetattr( slave, TCSAFLUSH, termp ) < 0 ) {
       perror( "tcsetattr" );
       exit( 1 );
     }
   }

+  if (0) {
   // we need to set initial window size, or TIOCGWINSZ fails
   struct winsize w;
   w.ws_row = 25;
@@ -131,6 +132,7 @@ pid_t my_forkpty( int *amaster, char *name,
       exit( 1 );
     }
   }
+  }

   pid = fork();
   switch ( pid ) {
