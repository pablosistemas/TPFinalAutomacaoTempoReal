#!/usr/bin/perl -w

# Cria FIFOS padrao SystemV: 
# "gateway_historiador" "historiador_servapp" "servapp_historiador"
# Recebe mensagens de posicionamento no padrao struct position_t
# do gateway, armazena as informacoes no banco de dados local
# e responde requisicoes do servidor (fifo servapp_historiador)
# pela fifo historiador_servapp. 

use strict;
use POSIX qw(mkfifo O_RDONLY O_NONBLOCK O_WRONLY);
use IO::Select;
use IPC::SysV;

# database
use DBI;

sub POSITION_T_LEN { return 36; }
sub MAX_POSITION_SAMPLES { return 30; }

# retorna struct C:
# struct {
# int a;
# int b;
# };

sub historiador_4_servapp {
   my $msg_ptr = shift;
   my $hs;
   sysopen ($hs, "historiador_servapp", O_WRONLY | O_NONBLOCK);
   print $hs ${$msg_ptr};
   close ($hs);
}

sub cria_historical_data_reply_t {
   my $dbh_ptr = shift;
   my $id_ptr  = shift;
   my $samples_ptr = shift;

   # cria schema
   # todos devem ser diferentes de NULL
   my $stmt = qq ( SELECT * FROM CLIENTES WHERE id=${$id_ptr} ORDER BY ROWID DESC LIMIT ${$samples_ptr});
   #my $sel_str = "SELECT * FROM CLIENTES WHERE id=${$id_ptr}";
   #${$dbh_ptr}->do(); 

   my $sth  = ${$dbh_ptr}->prepare( $stmt );
   my $rv   = $sth->execute() or die "Erro criacao tabela\n";

   if ($rv < 0) {
      print "Erro $DBI::errstr\n";
      trap();
   }
   
   # retorna uma ref para array de refs da linhas da consulta
   my $rows       = $sth->fetchall_arrayref;
   my $rows_len   = scalar @{$rows};
   my $stringResposta;
   if($rows_len < 1) {
      $stringResposta ="HIST;$rows_len";
   } else {
      $stringResposta ="HIST;$rows_len;${$id_ptr}";
   }
      
   foreach my $i (@{$rows}) {
      #print "ID         = $i->[1]\n";
      #print "TIMESTAMP  = $i->[2]\n";
      #print "LATITUDE   = $i->[3]\n";
      #print "LONGITUDE  = $i->[4]\n";
      #print "SPEED      = $i->[5]\n\n";
      # estado sempre 1????
      my $pos=";POS;$i->[2];$i->[3];$i->[4];$i->[5];1";
      $stringResposta=$stringResposta.$pos;
   }

   $stringResposta=$stringResposta."\n";

   print "resposta: ",$stringResposta;

   return $stringResposta;
}
   
sub ret_historical_data_request_t {
   my $args = shift;
   #return unpack('ll',${$args});
   my ($ret1, $ret2) = ${$args} =~ /^REQ_HIST;(\d+);(\d+)\s+/;
}

sub position_t_2_value {
   my $struct = shift;
   return unpack("lxxxxQddl", ${$struct});
}

unless (-p "historiador_servapp") {
   mkfifo("historiador_servapp", 0777) || die "mkfifo 1 failed\n";
}
   
unless (-p "servapp_historiador") {
   mkfifo("servapp_historiador", 0777) || die "mkfifo 2 failed\n";
}

unless (-p "gateway_historiador") {
   mkfifo("gateway_historiador", 0777) || die "mkfifo 3 failed\n";
}

# open() é blocante, outro lado deve estar aberto
my ($sh,$gh);
#open ($hs, "> historiador_servapp") or 
#   die "error open fifo 1\n";

print "sh\n";
#open ($sh, "< servapp_historiador") or 
#   die "error open fifo 2\n";
sysopen ($sh, "servapp_historiador", O_RDONLY | O_NONBLOCK);

print "gh\n";
#open ($gh, "< gateway_historiador") or 
#   die "error open fifo 3\n";
sysopen ($gh, "gateway_historiador", O_RDONLY | O_NONBLOCK);

my $selectObj = IO::Select->new();

# $selectObj->add($hs);
# fila servidor historiador
$selectObj->add($sh);
# fila gateway historiador
$selectObj->add($gh);

# cadastra interrupcao
$SIG{INT} = \&trap;

# abre base de dados
my $driver    = "SQLite";
my $database  = "position_t.db";
my $dsn = "DBI:$driver:dbname=$database";
my $userid  = "";
my $passwd  = "";
my $dbh = DBI->connect($dsn,$userid,$passwd,{ RaiseError => 1})
   or die $DBI::errstr;

print "Base de dados aberta com sucesso!\n";

# cria schema
# todos devem ser diferentes de NULL
# INTEGER PRIMARY KEY sets implicitily rowid key
my $stmt = qq (CREATE TABLE IF NOT EXISTS CLIENTES
   (  INTEGER        PRIMARY KEY,
      ID             KEY   NOT NULL,
      TIMESTAMP      TEXT  NOT NULL,
      LATITUDE       TEXT  NOT NULL,
      LONGITUDE      TEXT  NOT NULL,
      SPEED          TEXT  NOT NULL););

my $sth  = $dbh->prepare( $stmt );
my $rv   = $sth->execute() or die "Erro criacao tabela\n";
if ($rv < 0) {
   print "Erro $DBI::errstr\n";
   trap();
}
#my $dado;
#while(read($gh,$dado,36)){
#   if ($dado) {
#      print "lido alguma xoisa\n";
#   } else {
#      print "dada\n";
#   }
#}

# espera mensagens do servidor de aplicacao
while(my @ready = $selectObj->can_read) {
   foreach my $ready (@ready){
      if($ready == $sh) {
         my $data = <$sh>;
         #print "recebeu servapp: ",$data;
         if ($data){
            print "recebeu servapp: ",$data;
            my ($id, $numSamples) = 
                  ret_historical_data_request_t(\$data);
            # se nao enviado na mensagem
            unless(defined $numSamples) {
               $numSamples = MAX_POSITION_SAMPLES();
            }

            print "$id, $numSamples\n";
            my $struct = cria_historical_data_reply_t(\$dbh,
                  \$id,\$numSamples);

            print $struct,"\n";

            historiador_4_servapp(\$struct);
         }
      # msg do historiador com nova posicao de clientes   
      } elsif ($ready == $gh) {
         #my $recved = <$ready>;
         my $recved;
         sysread $ready, $recved, POSITION_T_LEN();  
         if($recved) {
            my ($id,$time,$lat,$lon,$speed) = 
                  position_t_2_value(\$recved);
            printf "%d, %d, %f, %f, %d\n", 
               $id, $time, $lat, $lon, $speed;
            # inserir na base de dados
            $stmt = qq( INSERT INTO CLIENTES (ID,TIMESTAMP,LATITUDE,LONGITUDE,SPEED)
            VALUES ($id,$time,$lat,$lon,$speed));
            my $rv = $dbh->do($stmt) or die $DBI::errstr;
            if ($rv < 0) {
               print "Erro $DBI::errstr\n";
               trap();
            }
         }
      }
   }
}

$dbh->disconnect;

sub trap {
   close ($sh);
   close ($gh);

   my $stmt = qq(SELECT id, timestamp, latitude, longitude, speed FROM CLIENTES);
   my $sth = $dbh->prepare( $stmt );
   my $rv  = $sth->execute() or die $DBI::errstr;
   unless($rv < 0) {
      while (my @row = $sth->fetchrow_array()){
         print "ID         = $row[0]\n";
         print "TIMESTAMP  = $row[1]\n";
         print "LATITUDE   = $row[2]\n";
         print "LONGITUDE  = $row[3]\n";
         print "SPEED      = $row[4]\n\n";
      }
   }

   $dbh->do("DROP TABLE CLIENTES");

   die "ByeBye!\n";
}


