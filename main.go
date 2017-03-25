package main

import (
	"bytes"
	"context"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/google/cadvisor/info/v2"
	"github.com/immesys/bwadvisor/cadvisor"
)

const SERVER = "http://lp.cal-sdb.org:8086/v1"

func main() {
	iface, err := cadvisor.New(0, "docker", "/")
	if err != nil {
		panic(err)
	}
	err = iface.Start()
	if err != nil {
		panic(err)
	}
	// evc, err := iface.WatchEvents(&events.Request{EventType: map[info.EventType]bool{info.EventContainerCreation: true}})
	// if err != nil {
	// 	panic(err)
	// }
	// for e := range evc.GetChannel() {
	// 	fmt.Printf("got event %#v\n", e)
	// }

	ident := os.Getenv("BWADVISOR_IDENTITY")
	if ident == "" {
		panic("need $BWADVISOR_IDENTITY")
	}
	queue = make(chan (*StatBundle), 10000)
	go publish(ident, "amd64")
	scrape(iface)

}

type StatBundle struct {
	Dat       []*v2.ContainerStats
	Container string
}

var queue chan (*StatBundle)

const ScrapeInterval = 10 * time.Second

func scrape(iface cadvisor.Interface) {
	lastScrape := make(map[string]time.Time)
	for {
		time.Sleep(ScrapeInterval)
		info, err := iface.ContainerInfoV2("/", v2.RequestOptions{IdType: "docker", Count: 60, Recursive: true})
		if err != nil {
			fmt.Printf("got CA error %v\n", err)
			continue
		}
		for _, ci := range info {
			good := false
			realname := "error"
			for _, a := range ci.Spec.Aliases {
				if regexp.MustCompile("bw2paper_.*").MatchString(a) {
					good = true
					realname = strings.TrimPrefix(a, "bw2paper_")
					break
				}
			}
			if !good {
				fmt.Printf("skipping container: %s\n", ci.Spec.Aliases)
				continue
			}

			ls := lastScrape[realname]
			sidx := 0
			for idx, e := range ci.Stats {
				if !e.Timestamp.After(ls) {
					sidx = idx
				}
			}
			lastScrape[realname] = ci.Stats[len(ci.Stats)-1].Timestamp

			fmt.Printf("Enqueing bundle for %s %d\n", realname, len(ci.Stats[sidx:]))
			queue <- &StatBundle{Dat: ci.Stats[sidx:], Container: realname}
		}
	}
}

type MF map[string]float64

func publish(ident string, arch string) {
	client := &http.Client{}
	for {
		e := <-queue
		buf := bytes.Buffer{}
		for _, stat := range e.Dat {
			mkln := func(grp string, unit string, ts time.Time, valz MF) {
				strz := []string{}
				for k, v := range valz {
					strz = append(strz, fmt.Sprintf("%s=%f", k, v))
				}
				role := "misc"
				st := strings.Join(strz, ",")
				if strings.HasPrefix(e.Container, "agent_") {
					role = "agent"
				}
				if strings.HasPrefix(e.Container, "tracer_") {
					role = "tracer"
				}
				ln := fmt.Sprintf("%s/%s/%s,unit=%s,arch=%s,role=%s %s %d\n", ident, e.Container, grp, unit, arch, role, st, ts.UnixNano())
				buf.Write([]byte(ln))
			}
			//CPU time
			mkln("cpu", "nanoseconds", stat.Timestamp, MF{
				"cpu_total":  float64(stat.Cpu.Usage.Total),
				"cpu_user":   float64(stat.Cpu.Usage.User),
				"cpu_system": float64(stat.Cpu.Usage.System),
			})
			//Memory
			mkln("mem", "bytes", stat.Timestamp, MF{
				"mem_total": float64(stat.Memory.Usage),
				"mem_ws":    float64(stat.Memory.WorkingSet),
			})
			//Firewall
			for customname, metricarray := range stat.CustomMetrics {
				if strings.Contains(customname, "go_") || strings.Contains(customname, "process") {
					continue
				}
				if len(metricarray) != 1 {
					continue
				}
				unit := "unk"
				grp := "misc"
				if strings.HasSuffix(customname, "bytes") {
					unit = "bytes"
					grp = "net/bytes"
					customname = strings.TrimSuffix(customname, "_bytes")
				}
				if strings.HasSuffix(customname, "pkts") {
					unit = "packets"
					grp = "net/packets"
					customname = strings.TrimSuffix(customname, "_pkts")
				}
				mkln(grp, unit, metricarray[0].Timestamp, MF{
					customname: float64(metricarray[0].FloatValue),
				})
			}
		}
		then := time.Now()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		req, err := http.NewRequest("POST", SERVER, &buf)
		if err != nil {
			panic(err)
		}
		req = req.WithContext(ctx)
		resp, err := client.Do(req)
		if err != nil {
			fmt.Printf("Failed err=%s\n", err)
			select {
			case queue <- e:
				fmt.Printf("Successfully requeued bundle")
			default:
			}
		} else {
			bdy, _ := ioutil.ReadAll(resp.Body)
			defer resp.Body.Close()
			if resp.StatusCode != 200 {
				fmt.Printf("Failed: %s\n", string(bdy))
				select {
				case queue <- e:
					fmt.Printf("Successfully requeued bundle")
				default:
				}
			} else {
				fmt.Printf("Published ok %s\n", time.Now().Sub(then))
			}
		}
		// stat = e.Dat[0]
		// col, nam := mkcn(e.CE, e.Container, "cpu", "usage")
		// report(col, nam, stat.Timestamp, float64(stat.Cpu.Usage.Total), "cputime")
		// col, nam = mkcn(e.CE, e.Container, "memory", "usage")
		// report(col, nam, stat.Timestamp, float64(stat.Memory.Usage), "bytes")
		// for cmn, marr := range stat.CustomMetrics {
		// 	if strings.Contains(cmn, "go_") || strings.Contains(cmn, "process") {
		// 		continue
		// 	}
		// 	unit := "unk"
		// 	col, nam = mkcn(e.CE, e.Container, "misc", cmn)
		// 	if strings.HasSuffix(cmn, "bytes") {
		// 		col, nam = mkcn(e.CE, e.Container, "ipf/bytes", strings.TrimSuffix(cmn, "_bytes"))
		// 		unit = "bytes"
		// 	}
		// 	if strings.HasSuffix(cmn, "pkts") {
		// 		col, nam = mkcn(e.CE, e.Container, "ipf/pkts", strings.TrimSuffix(cmn, "_pkts"))
		// 		unit = "packets"
		// 	}
		//
		// 	report(col, nam, marr[0].Timestamp, float64(marr[0].FloatValue), unit)
		// }
		// fmt.Printf("buffered package for %s %s\n", e.CE.Collection, e.Container)
		// //	stat.Cpu.Usage.Total
	}
}
