all: servidor

servidor: 
	go build
	export GOPATH=`pwd`

clean:
	rm historiador_servapp servapp_historiador gateway_historiador position_t.db TPFinalAutomacaoTempoReal
