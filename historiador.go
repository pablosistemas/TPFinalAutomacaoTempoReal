package main

import (
	"database/sql"
	"fmt"
	"regexp"

	_ "go-sqlite3"
)

const (
	maxPositionSamples = 30
)

type historicalDataRequest struct {
	ID         string
	NumSamples string
}

type historicalDataReply struct {
	NumSamplesAvailable string
	Position            [maxPositionSamples]position
}

func parseHistRequest(str []byte) (id string, samples string) {

	r, _ := regexp.Compile("REQ_HIST;(\\d*);(\\d*)")
	submatch := r.FindStringSubmatch(string(str))
	id = submatch[1]
	samples = submatch[2]
	// id, _ = strconv.Atoi(submatch[1])
	// samples, _ = strconv.Atoi(submatch[2])
	return
}

type rsp struct {
	ID        string
	Timestamp string
	Lat       string
	Long      string
	Speed     string
}

func runHistoricalServerConnection(request []byte) (response string) {

	var rsps []rsp
	db, err := sql.Open("sqlite3", "./test.db")
	if err != nil {
		fmt.Println("Error on connection string", err.Error())
		return ""
	}
	defer db.Close()
	id, samples := parseHistRequest(request)
	queryStr := fmt.Sprintf("SELECT `ID`, `TIMESTAMP`, `LATITUDE`, `LONGITUDE`, `SPEED` FROM CLIENTES WHERE `ID`=%s ORDER BY `ROWID` DESC LIMIT %s", id, samples)
	rows, err := db.Query(queryStr)
	defer rows.Close()

	if err != nil {
		fmt.Println(err)
	}

	for rows.Next() {
		var rowID string
		var timestamp string
		var lat string
		var long string
		var speed string
		err = rows.Scan(&rowID, &timestamp, &lat, &long, &speed)
		var data = struct {
			ID        string
			Timestamp string
			Lat       string
			Long      string
			Speed     string
		}{ID: rowID, Timestamp: timestamp, Lat: lat, Long: long, Speed: speed}
		rsps = append(rsps, data)
	}

	response = fmt.Sprintf("HIST;%d;%s", len(rsps), id)
	for _, d := range rsps {
		response += fmt.Sprintf(";POS;%s;%s;%s;%s;%d", d.Timestamp, d.Lat, d.Long, d.Speed, 1)
	}

	return

}
