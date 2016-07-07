package main

import (
	"fmt"
	"regexp"
)

// Descricao das mensagens do protocolo usado na comunicacao entre servidor e interface grafica

const (
	// Recebido da interface
	reqAtivos = "REQ_ATIVOS"

	// Recebido do Historiador
	reqHist = "REQ_HIST"
)

type positionData struct {
	DateTime string
	Lat      string
	Long     string
	Vel      string
	State    string
}

// Servidor responde com mensagen no formato de
// ATIVOS;<NUM>;<ID1>;<ID2>;...;<IDN>
func mountActiveClientsResponse(actives []string) (msg string) {

	msg = fmt.Sprintf("ATIVOS;%d", len(actives))

	// Returns ATIVOS;0 if empty array
	if len(actives) == 0 {
		msg += "\n"
		return
	}

	for _, active := range actives {
		msg += ";" + active + ";" + active
	}
	// msg += '\n'
	msg += fmt.Sprintf("%c", '\n')
	return
}

// Servidor responde com mensagem historica no formato
// HIST;<NUM>;<ID>;<POS1>;<POS2>;...;<POSN>   onde
// POS;<DT>;<LAT>;<LON>;<VEL>;<ESTADO>
func mountHistoricsResponse(posData []positionData, id string) (msg string) {
	msg = fmt.Sprintf("HIST;%d;%s", len(posData), id)
	// Returns ATIVOS;0 if empty array
	if len(posData) == 0 {
		msg = fmt.Sprintf("%s;0\n", "HIST")
		return
	}

	for _, data := range posData {
		msg += fmt.Sprintf(";POS;%s;%s;%s;%s;%s",
			data.DateTime, data.Lat, data.Long, data.Vel, data.State)

	}
	msg += "\n"

	return
}

func parseRequestMessage(str []byte) string {
	r, _ := regexp.Compile("\\s*(\\w*)")
	submatch := r.FindStringSubmatch(string(str))

	return submatch[1]
}
