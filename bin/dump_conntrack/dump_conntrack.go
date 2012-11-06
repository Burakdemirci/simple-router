package main

import (
	"github.com/dominikh/simple-router/conntrack"

	"encoding/gob"
	"os"
)

func main() {
	flows, err := conntrack.Flows()
	if err != nil {
		panic(err)
	}

	encoder := gob.NewEncoder(os.Stdout)
	encoder.Encode(flows)
}
