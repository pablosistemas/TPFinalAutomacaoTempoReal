#!/usr/bin/perl

use strict;
use Socket;
use threads;

use constant SIMPLE_TCP_PORT  => 8000;
use constant MAX_RECV_LEN     => 65536;
use constant NUM_THREADS      => 20;
use constant NUM_MSG          => 3;

# envia mensagens de posicionamento para o gateway da aplicacao.
# As mensagens HTTP sao enviadas para o historiador no formato 
# especificados na struct position_t:
# struct position_t {
#  int id;
#  time_t timestamp;
#  double latitude;
#  double longitude;
#  int speed;
#  };
#  O gateway envia mensagens para o servidor de aplicacao da posicao
#  mais recente dos clientes a cada mensagem recebida de algum deles.

my $remote = '127.0.0.1';

my $trans_serv    = getprotobyname('tcp');
my $remote_host   = gethostbyname ( $remote ) or 
   die "falha gethostbyname: $!\n";

# lanca N threads para se conectarem ao servidor
my $nthr;
my @threads;
for ($nthr=0; $nthr < NUM_THREADS; $nthr++){
   my @arg_th;
   # argumentos: protocolo, numero thread
   push @arg_th, $nthr;
   push @arg_th, $trans_serv;

   my $destino = sockaddr_in (SIMPLE_TCP_PORT,$remote_host); 
   #INADDR_ANY);
   push @arg_th, $destino;

   my $t = threads->create(\&start_sub, @arg_th);
   push @threads, $t;
}

for ($nthr=0; $nthr < NUM_THREADS; $nthr++){
   $threads[$nthr]->join();
}

exit(1);

sub start_sub {
   my @args = @_;

   socket (TCP_SOCK, PF_INET, SOCK_STREAM, $args[1]) or 
      die "erro no socket(): $!\n";

   connect (TCP_SOCK, $args[2]) or die "Erro connect() : $!\n";
   
   for(my $i = 0; $i < NUM_MSG; $i++){
      my $timestamp  = int(rand(2**32)); 
      my $lat        = rand(90);  
      my $lon        = (-1)*rand(90);  
      my $msg = "GET /?id=$args[0]&timestamp=$timestamp";
      $msg = $msg."&lat=$lat&lon=$lon";
      $msg = $msg."&speed=0.0&bearing=0.0&altitude=819.0&batt=91.0 ";
      $msg = $msg."HTTP/1.1\r\nUser-Agent: Dalvik/2.1.0 ";
      $msg = $msg."(Linux; U; Android 6.0; Nexus 5 Build/MRA58N)\r\n";
      $msg = $msg."Host: 150.164.35.70:9001\r\n";
      $msg = $msg."Connection: Keep-Alive\r\n";
      $msg = $msg."Accept-Encoding: gzip\r\n\r\n";

      send (TCP_SOCK, $msg, 0);
      my $resp = <TCP_SOCK>;
      if($resp) {
         $resp = $resp.<TCP_SOCK>; # Content-Length
         $resp = $resp.<TCP_SOCK>; # Keep-Alive
         $resp = $resp.<TCP_SOCK>; # \r\n
         print "Veiculo $args[0] receceu resposta do gateway:\n",$resp;
      }
      sleep (1);
   }
   close (TCP_SOCK);
   #yield();
}
