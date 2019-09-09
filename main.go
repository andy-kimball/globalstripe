package main

import (
	"bytes"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
)

var ParamNotFoundError = errors.New("query parameter not found")

type Request events.APIGatewayProxyRequest
type Response events.APIGatewayProxyResponse

func (r *Request) IntParameter(name string) (int, error) {
	param, ok := r.QueryStringParameters[name]
	if !ok {
		return 0, ParamNotFoundError
	}
	i, err := strconv.Atoi(param)
	if err != nil {
		return 0, fmt.Errorf("%s parameter is not a valid integer: %s", name, param)
	}
	return i, nil
}

type Account struct {
	Id        string
	Email     string
	CreatedAt time.Time `db:"created_at"`
}

type Charge struct {
	Region    string
	AccountId string    `db:"account_id"`
	Id        string
	Amount    float64
	Currency  string
	Last4     string
	Outcome   string
	CreatedAt time.Time `db:"created_at"`
}

var db *sqlx.DB

func init() {
	var err error
	db, err = sqlx.Open(
		"postgres",
		"postgresql://globalstripe@globalstripedb.demo.cockroachdb.dev:26257/globalstripe?ssl=true&sslmode=require&password=5B57E9F2-A7E9-46DA-B1D2-448334CC6233")
	if err != nil {
		log.Fatal("error connecting to the database: ", err)
	}
}

// GET /accounts
func listAccounts(request Request) Response {
	return authenticate(request, func(account Account) Response {
		return makeResponse(200, account)
	})
}

// POST /charges
func createCharge(request Request) Response {
	return authenticate(request, func(account Account) Response {
		values, err := decodePostBody(request)
		if err != nil {
			return badRequestResponse(err.Error())
		}

		// This is where the issuer would be contacted to authorize the charge.

		// Save only last 4 digits of card number.
		cardNumber := values.Get("card_number")
		if len(cardNumber) < 4 {
			return badRequestResponse("card_number is missing or invalid")
		}
		last4 := cardNumber[len(cardNumber)-4:]

		// Pretend that if last digit of card is even, then charge would be always
		// be authorized. If odd, it's declined.
		var outcome string
		if last4[len(last4)-1] % 2 == 0 {
			outcome = "authorized"
		} else {
			outcome = "issuer_declined"
		}

		amount := values.Get("amount")
		currency := values.Get("currency")

		var charge Charge
		text :=
			"INSERT INTO charges " +
				"(amount, currency, last4, outcome, account_id, created_at) " +
				"VALUES ($1, $2, $3, $4, $5, current_timestamp()) " +
				"RETURNING region, id, amount, currency, last4, outcome, account_id, created_at"
		if err = db.Get(&charge, text, amount, currency, last4, outcome, account.Id); err != nil {
			return badRequestResponse(fmt.Sprintf("invalid post data: %v", err))
		}

		return makeResponse(201, charge)
	})
}

// GET /charges
func listCharges(request Request) Response {
	return authenticate(request, func(account Account) Response {
		limit, err := request.IntParameter("limit")
		if err == ParamNotFoundError {
			limit = 100
		} else if err != nil {
			return badRequestResponse("limit must be an integer")
		}

		var charges []Charge
		text :=
			"SELECT region, id, amount, currency, last4, outcome, account_id, created_at " +
				"FROM charges " +
				"WHERE account_id = $1 " +
				"ORDER BY created_at DESC " +
				"LIMIT $2"
		if err := db.Select(&charges, text, account.Id, limit); err != nil {
			panic(err)
		}
		return makeResponse(200, charges)
	})
}

// GET /charges/{id}
func getCharge(request Request) Response {
	return authenticate(request, func(account Account) Response {
		id := request.PathParameters["id"]

		// Start by assuming charge is in the current region, for fast lookup.
		var charge Charge
		text :=
			"SELECT region, id, amount, currency, last4, outcome, account_id, created_at " +
				"FROM charges " +
				"WHERE region = crdb_internal.locality_value('region') AND id = $1 AND account_id = $2"
		if err := db.Get(&charge, text, id, account.Id); err == nil {
			return makeResponse(200, charge)
		} else if err != sql.ErrNoRows {
			panic(err)
		}

		text =
			"SELECT region, id, amount, currency, last4, outcome, account_id, created_at " +
				"FROM charges " +
				"WHERE id = $1 AND account_id = $2"
		if err := db.Get(&charge, text, id, account.Id); err == nil {
			return makeResponse(200, charge)
		} else if err != sql.ErrNoRows {
			panic(err)
		}

		return notFoundResponse("charge")
	})
}

func authenticate(request Request, fn func(account Account) Response) Response {
	auth, ok := request.Headers["Authorization"]
	if !ok {
		return accessDeniedResponse("no secret key was supplied")
	}

	fields := strings.Split(auth, " ")
	if len(fields) != 2 {
		return badRequestResponse("authorization header value did not have two fields")
	}

	sum := sha256.Sum256([]byte(fields[1]))
	secret_key_digest := base64.URLEncoding.EncodeToString(sum[:])

	var account Account
	text := "SELECT id, email, created_at FROM accounts WHERE secret_key_digest = $1"
	if err := db.Get(&account, text, secret_key_digest); err != nil {
		return accessDeniedResponse("secret key does not match any account")
	}

	return fn(account)
}

func decodePostBody(request Request) (values url.Values, err error) {
	values, err = url.ParseQuery(request.Body)
	if err != nil {
		err = fmt.Errorf("error parsing post body: %v", err)
	}
	return values, err
}

func accessDeniedResponse(reason string) Response {
	return makeResponse(401, fmt.Sprintf("401 (Access Denied): %s", reason))
}

func badRequestResponse(reason string) Response {
	return makeResponse(400, fmt.Sprintf("400 (Bad Request): %s", reason))
}

func notFoundResponse(reason string) Response {
	return makeResponse(404, fmt.Sprintf("404 (Not Found): %s", reason))
}

// Handler is our lambda handler invoked by the `lambda.Start` function call
func Handler(request Request) (Response, error) {
	switch request.HTTPMethod {
	case "GET":
		switch request.Resource {
		case "/accounts":
			return listAccounts(request), nil

		case "/charges":
			return listCharges(request), nil

		case "/charges/{id}":
			return getCharge(request), nil
		}

	case "POST":
		switch request.Resource {
		case "/charges":
			return createCharge(request), nil
		}

	default:
		log.Fatal("unknown method")
	}

	log.Fatal("unknown resource")
	return Response{}, nil
}

func makeResponse(status int, val interface{}) Response {
	var buf bytes.Buffer
	body, err := json.Marshal(val)
	if err != nil {
		log.Fatal(err)
	}
	json.HTMLEscape(&buf, body)
	return Response{
		StatusCode:      status,
		IsBase64Encoded: false,
		Body:            buf.String(),
		Headers: map[string]string{"Content-Type": "application/json"},
	}
}

func main() {
	lambda.Start(Handler)
}
