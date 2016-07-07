#!/usr/bin/perl -w
use IO::Socket;
use IO::Select;
use IPC::SysV qw( IPC_PRIVATE IPC_RMID S_IRUSR S_IWUSR IPC_CREAT IPC_EXCL );

use strict;
use warnings;

use constant MAX_RECV_LEN  => 1500;
# LIST_SIZE da o tamanho em bits. shmget arredonda para multiplo
# de PAGE_SIZE
use constant LIST_SIZE => 1000;

sub position_t_len {
# string pack: "lxxxxQddl"
   # use essa linha para structs "desalinhadas" 
   return (32+32+64+64+64+32)/8; 
   # use essa linha para structs "alinhadas" 
   #return (32+32+64+64+64)/8; 
}

# UDDI - proto para publicacao e procura de serviços
# WSDL - ling para descricao dos servicos e como acessa-los
# instalar Apache WebServer

my $gateway_obj = IO::Socket::INET->new ( 
   LocalPort   => shift || 8000,
   Listen      => SOMAXCONN, 
   Proto       => 'tcp') or die "erro em gateway_obj\n";

my $servapp_obj = IO::Socket::INET->new ( 
   PeerPort   => 7001,
   PeerAddr   => '127.0.0.1',
   Reuse      => 1, 
   Proto      => 'tcp') or die "erro em servapp_obj\n";

# se receber Ctrl-C, fecha conexoes
$SIG{INT} = \&trata_evento;

############## DEBUG ##############
#my $aguenta_coracao = <>;
#trata_evento();
############## DEBUG ##############

my $read_handlers = IO::Select->new();
$read_handlers->add($gateway_obj);

my $data;
my $fhandler;

# referencias para array
my $conn;

my %cliaddr2id;

while( 1 ) {
   my @readable = $read_handlers->can_read();

   # se nova conexão, enfileira novo socket e o add no select
   foreach $fhandler (@readable) {
      if ($fhandler == $gateway_obj) {
         print "Nova conn aceita!\n";
         $conn = $gateway_obj->accept();
         
         $read_handlers->add ($conn);
      } else {
         # recebe todas as partes da mensagem http
         $data = <$fhandler>; #GET
         if ($data) {
         # se nao eh fim de conn, recebe restante da msg 
            $data = $data.<$fhandler>; #User-Agent
            $data = $data.<$fhandler>; #Host
            $data = $data.<$fhandler>; #Connection
            $data = $data.<$fhandler>; #Accept-Encoding
            $data = $data.<$fhandler>; #\r\n

            my $struct_hist = decode_msg($data);

            # se ha algum erro no parsing, nao interpretamos a msg
            unless (defined($struct_hist)) {
               print "Erro na mensagem\n";
               next;
            } else {
               print $data,"\n";
            
               # responde o cliente
               print $fhandler "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nKeep-Alive: timeout=15,max=100\r\n\r\n";

               # escreve dado atualizado para historiador
               grava_pos_fifo($struct_hist);
               
               # envia dado atualizado para servidor de aplicacao

               envia_position_t_servapp($struct_hist);
               print "enviando mensagem para o servidos app\n";

               # se o ID desse par nao esta na lista, adiciona
               unless (defined($cliaddr2id{$fhandler})) {
                  $cliaddr2id{$fhandler} = 
                        unpack("l",$struct_hist);
               }
            }
         } else {
            # remove o socket da lista do select()
            $read_handlers->remove($fhandler);

            # envia dado atualizado para servidor de aplicacao
            my $struct_zero = 
               cria_position_t_struct($cliaddr2id{$fhandler},0,0,0,0);
            envia_position_t_null_servapp($struct_zero);

            # seta o id para -1 desse cliente
            # TODO
            $cliaddr2id{$fhandler} = undef; 

         }
      }
   }
}

# inserir em destrutor da classe
$gateway_obj->close;

sub decode_msg {
   my $msg = shift;

   #my ($IMEI,$DT) = $msg =~ /^GET\s\/?<id=(.+)&timestamp=(\d+)>/;
   my ($IMEI,$DT,$LAT,$LON,$VEL,$BEAR,$ALT,$BAT) = 
      $msg =~ /^GET\s\/\?id=(.+)
      &timestamp=(\d+)&lat=([\+|-]*\d+\.\d+)
      &lon=([\+|-]*\d+\.\d+)&speed=(\d+\.*\d*)&bearing=(\d+\.*\d*)
      &altitude=(\d+\.*\d*)&batt=(\d+\.\d+)\sHTTP\/1\.1\r\n
      User\-Agent:\s.+\r\n
      Host:\s\d+\.\d+\.\d+\.\d+:\d+\r\n
      Connection:\sKeep\-Alive\r\n
      Accept\-Encoding:\sgzip\r\n\r\n/x;
   
   #\sHTTP\/1.1\r\nUser-Agent:\s<>/;
   print $IMEI," ",$DT," ",$LAT," ",$LON," ",$VEL," ",$BEAR,
      " ",$ALT," ",$BAT,"\n";

   #printf "%d %x %ld %ld %d %d %d %f\n",
   #   $IMEI,$DT,$LAT,$LON,$VEL,$BEAR,$ALT,$BAT;

   if (defined($IMEI) && defined($DT) && defined($LAT) && defined($LON)
         && defined($VEL) && defined($BEAR) && defined($ALT) &&
         defined($BAT)) {
      return cria_position_t_struct ($IMEI,$DT,$LAT,$LON,$VEL);
   } else {
      return undef;
   }
}

sub grava_arquivo {
   my $struct = shift;

   open (my $fh, ">", 'file.txt');

   print $fh $struct;

   close($fh);
}

# se o outro lado nao estiver com o descritor da fifo aberto
# bloqueia execucao ate q alguem abra a fifo para leitura
sub grava_pos_fifo {
   my $struct = shift;
   my $fh;

   unless (open ($fh, ">", 'gateway_historiador')) {
      print "Erro na abertura da fifo\n";
      trata_eventos();
   }

   print $fh $struct;

   close($fh);
}

# empacota:
# struct {
#  int id;
#  time_t timestamp;
#  double latitude;
#  double longitude;
#  int speed;
# }
# return pack ("lxxxxQddl",$IMEI,$DT,$LAT,$LON,$VEL);
# return pack ("llQdd",$IMEI,$VEL,$DT,$LAT,$LON);

sub cria_position_t_struct {
   my $IMEI = shift;
   my $DT   = shift;
   my $LAT  = shift;
   my $LON  = shift;
   my $VEL  = shift; 

   return pack ("lxxxxQddl",$IMEI,$DT,$LAT,$LON,$VEL);
   #return pack ("llQdd",$IMEI,$VEL,$DT,$LAT,$LON);
}

sub envia_position_t_servapp {
   my $struct = shift;
   my ($id,$time,$lat,$lon,$speed) = unpack("lxxxxQddl",$struct);
   my $msg="UPDATE&id=$id&timestamp=$time&lat=$lat&lon=$lon&speed=$speed\n";
   #unless (print $servapp_obj $struct) {
   #unless ($servapp_obj->write($struct, position_t_len())) {
   #unless (print $servapp_obj "teste\n") {
   unless (print $servapp_obj $msg) {
      print "Erro em envia_position_t_servapp\n";
      trata_evento();
   }
}

sub envia_position_t_null_servapp {
   my $struct = shift;
   my ($id,$time,$lat,$lon,$speed) = unpack("lxxxxQddl",$struct);
   my $msg="DELETE&id=$id&timestamp=$time&lat=$lat&lon=$lon&speed=$speed\n";
   #unless (print $servapp_obj $struct) {
   #unless ($servapp_obj->write($struct, position_t_len())) {
   #unless (print $servapp_obj "teste\n") {
   unless (print $servapp_obj $msg) {
      print "Erro em envia_position_t_servapp\n";
      trata_evento();
   }
}

sub trata_evento {
   my $signame = shift;
   # fecha socket
   $gateway_obj->close;
   $servapp_obj->close;

   print "Adios!\n";
   exit -1;
}
