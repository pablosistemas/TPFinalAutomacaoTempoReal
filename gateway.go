package main

import "regexp"

// Used to obtain data on:
//  Num of active users
//  List with position data

type position struct {
	ID        string
	Timestamp string
	Latitude  string
	Longitude string
	Speed     string
}

var (
	numSamples   int
	positionList map[string]position
)

func retrieveActiveIDs() (ids []string) {

	for _, pos := range positionList {
		ids = append(ids, pos.ID)
	}
	return
}

func parseGatewayRequestType(request []byte) string {
	r, _ := regexp.Compile("(\\w*)&")
	return r.FindStringSubmatch(string(request))[1]
}

func parseGatewayPosition(request []byte) (pos position) {
	r, _ := regexp.Compile("\\w*&id=(\\d*)&timestamp=(\\d*)&lat=([+\\-\\d.]*)&lon=([+\\-\\d.]*)&speed=(\\d*)")
	submatch := r.FindStringSubmatch(string(request))
	pos.ID = submatch[1]
	pos.Timestamp = submatch[2]
	pos.Latitude = submatch[3]
	pos.Longitude = submatch[4]
	pos.Speed = submatch[5]

	return pos
}

func parseGatewayID(request []byte) (id string) {
	r, _ := regexp.Compile("\\w*&id=(\\d*)")
	submatch := r.FindStringSubmatch(string(request))
	id = submatch[1]
	return
}
