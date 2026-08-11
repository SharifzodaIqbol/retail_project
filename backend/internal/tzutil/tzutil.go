package tzutil

import (
	"log"
	"time"
)

var Location *time.Location

func init() {
	loc, err := time.LoadLocation("Asia/Dushanbe")
	if err != nil {
		log.Printf("tzutil: не удалось загрузить Asia/Dushanbe (%v), использую фиксированный UTC+5", err)
		loc = time.FixedZone("UTC+5", 5*60*60)
	}
	Location = loc
}

func Now() time.Time {
	return time.Now().In(Location)
}
