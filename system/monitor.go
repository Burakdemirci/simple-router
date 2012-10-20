package system

import (
	"github.com/dominikh/simple-router/hwmon"
	"github.com/dominikh/simple-router/memory"
	"github.com/dominikh/simple-router/monitor"
	"net"
	"time"
)

type InterfaceData struct {
	LAN *net.Interface
	WAN *net.Interface
}

type Data struct {
	Memory       memory.Stats
	Interfaces   InterfaceData
	Temperatures map[string]float64
}

func NewMonitor(delay time.Duration) *monitor.Monitor {
	return monitor.NewMonitor(delay, func(m *monitor.Monitor) {
		for {
			memory := memory.GetStats()

			lanEth, _ := net.InterfaceByName("eth1")
			wanEth, _ := net.InterfaceByName("eth0")

			iData := InterfaceData{lanEth, wanEth}

			mon1 := hwmon.HWMon{"hwmon0", []string{"2", "3"}}
			mon2 := hwmon.HWMon{"hwmon1", []string{"1"}}

			temps1, err := mon1.Temperatures()
			if err != nil {
				panic(err)
			}
			temps2, err := mon2.Temperatures()
			if err != nil {
				panic(err)
			}

			allTemps := make(map[string]float64)
			for key, value := range temps1 {
				allTemps[key] = value
			}

			for key, value := range temps2 {
				allTemps[key] = value
			}

			data := Data{memory, iData, allTemps}

			m.SendData(&data)

			time.Sleep(m.Delay)
		}
	})
}