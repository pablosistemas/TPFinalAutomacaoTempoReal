use strict;
use warnings;
use IPC::SysV;
use POSIX;

# programa para testar comunicação entre servidor de aplicacao e 
# historiador no envio e recebimento de mensagens REQ_HIST

# utiliza comunicacao gateway_historiador para popular base de dados
# para teste posterior do servidor de aplicacao

my ($sh,$hs);
sysopen ($hs,"historiador_servapp",O_RDONLY | O_NONBLOCK);

# popula base de dados
my $data;
for (my $i=0; $i < 100; $i++) {
   sysopen (my $ghwrite,"gateway_historiador",O_WRONLY | O_NONBLOCK);
   $data = pack("lxxxxQddl",int(rand(10)),int(rand(999)), 
         rand(123),rand(123),int(rand(112)));
   syswrite $ghwrite, $data, 36;
   close ($ghwrite);
}

# faz consultas
#my ($sh,$hs);

for(my $j=0; $j<10; $j++){
   my $query=int(rand(10));
   print "REQ_HIST;$query;15\n";

   sysopen ($sh,"servapp_historiador",O_WRONLY);
   print $sh "REQ_HIST;$query;5\n";
   close ($sh);
   sleep 1;
   my $resposta = <$hs>;
   if($resposta){
      print "HISTORIADOR->SERVIDOR\n";
      print $resposta,"\n";
   }
}

close ($hs);
