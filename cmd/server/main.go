package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/joho/godotenv"
)

func main() {
	conn, err := pgx.Connect(context.Background(), os.Getenv("DATABASE_URL"))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Не удалось подключиться к БД %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(context.Background())
	fmt.Println("Успешное подключение к базе данных!")
}
func init() {
	if err := godotenv.Load(); err != nil {
		log.Print("No .env file found")
	}
}
