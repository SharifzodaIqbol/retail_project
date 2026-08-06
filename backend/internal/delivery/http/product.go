package http

import (
	"context"
	"fmt"
	"net/http"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/repository"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
)

// parsePagination читает ?page=N&limit=M из query string.
// defaultLimit — значение по умолчанию; maxLimit — потолок, чтобы клиент не мог запросить слишком много.
func parsePagination(c *gin.Context, defaultLimit, maxLimit int) (page, limit int) {
	page, _ = strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	limit, _ = strconv.Atoi(c.DefaultQuery("limit", strconv.Itoa(defaultLimit)))
	if limit < 1 {
		limit = defaultLimit
	}
	if limit > maxLimit {
		limit = maxLimit
	}
	return
}

// buildPage оборачивает срез данных в стандартный paginatedResponse.
func buildPage(data interface{}, total, page, limit int) gin.H {
	totalPages := total / limit
	if total%limit != 0 {
		totalPages++
	}
	return gin.H{
		"data":        data,
		"total":       total,
		"page":        page,
		"limit":       limit,
		"total_pages": totalPages,
	}
}

// normalizeUnit — приводит значение колонки "единица" из Excel к внутреннему
// коду unit. Понимает русские обозначения (шт/штук/штука, кг/килограмм) и сами
// внутренние коды pcs/kg. Если ячейка пустая — считаем, что это штуки (старое
// поведение системы, где единица измерения по умолчанию была "шт").
func normalizeUnit(raw string) (string, error) {
	v := strings.ToLower(strings.TrimSpace(raw))
	switch v {
	case "", "шт", "шт.", "штук", "штука", "штуки", "pcs", "pc":
		return domain.UnitPcs, nil
	case "кг", "кг.", "килограмм", "килограммы", "kg":
		return domain.UnitKg, nil
	default:
		return "", fmt.Errorf("неизвестная единица измерения %q (ожидается 'шт' или 'кг')", raw)
	}
}

func parseImportFloat(raw string) (float64, error) {
	v := strings.TrimSpace(raw)
	v = strings.ReplaceAll(v, " ", "")
	v = strings.ReplaceAll(v, ",", ".") // в Excel часто десятичная запятая
	if v == "" {
		return 0, nil
	}
	return strconv.ParseFloat(v, 64)
}

// parseExtraUnitColumns — читает ДОПОЛНИТЕЛЬНЫЕ единицы продажи товара из
// колонок, идущих за старым фиксированным форматом (индексы 0..5: название,
// штрихкод, цена закупки, цена продажи, остаток, единица). Это сделано
// строго добавлением новых колонок в конец строки, а не переработкой
// старого формата — старые файлы (без этих колонок) читаются как раньше и
// продолжают создавать только базовую единицу "шт"/"кг".
//
// Формат: каждая доп. единица продажи — это группа из 4 колонок подряд,
// начиная с индекса 6:
//
//	[6] label              — например "упаковка"
//	[7] conversion_factor  — сколько базовых единиц (шт) в ней, например 20
//	[8] price              — цена именно за эту единицу продажи
//	[9] barcode            — необязательно, может быть пустым
//
// Далее группы по 4 колонки могут повторяться (10-13, 14-17...) для
// описания ещё одной единицы продажи того же товара в этой же строке.
func parseExtraUnitColumns(row []string) ([]domain.CreateProductUnitRequest, error) {
	var units []domain.CreateProductUnitRequest
	const groupStart = 6
	const groupSize = 4

	for start := groupStart; start < len(row); start += groupSize {
		get := func(offset int) string {
			idx := start + offset
			if idx < len(row) {
				return row[idx]
			}
			return ""
		}
		label := strings.TrimSpace(get(0))
		if label == "" {
			// Пустая группа колонок — просто нет ещё одной единицы продажи
			// в этой строке, это нормально, а не ошибка.
			continue
		}
		factor, err := parseImportFloat(get(1))
		if err != nil || factor <= 0 {
			return nil, fmt.Errorf("единица продажи %q: неверный коэффициент пересчёта %q", label, get(1))
		}
		price, err := parseImportFloat(get(2))
		if err != nil {
			return nil, fmt.Errorf("единица продажи %q: неверная цена %q", label, get(2))
		}
		var barcode *string
		if b := strings.TrimSpace(get(3)); b != "" {
			barcode = &b
		}
		units = append(units, domain.CreateProductUnitRequest{
			Label:            label,
			ConversionFactor: factor,
			Price:            price,
			Barcode:          barcode,
		})
	}
	return units, nil
}

// importProducts — массовая загрузка товаров из Excel-файла (.xlsx).
// Обязательные колонки (фиксированный порядок, первая строка — заголовок и
// пропускается): название | штрихкод | цена закупки | цена продажи | остаток | единица.
// Это ровно старый формат — обратная совместимость полная, старые файлы
// продолжают работать без изменений.
//
// Дополнительно (опционально), начиная с колонки 6, можно описать другие
// единицы продажи того же товара группами по 4 колонки — см.
// parseExtraUnitColumns. Товар с уже существующим в компании штрихкодом
// обновляется, иначе создаётся новый.
func (h *Handler) importProducts(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)

	fileHeader, err := c.FormFile("file")
	if err != nil {
		logWarn(c, "Импорт товаров: файл не передан", "error", err.Error())
		c.JSON(400, gin.H{"error": "Файл не найден. Отправьте поле 'file' с Excel-файлом (.xlsx)"})
		return
	}

	f, err := fileHeader.Open()
	if err != nil {
		logErr(c, err, "Импорт товаров: не удалось открыть загруженный файл", "filename", fileHeader.Filename)
		c.JSON(400, gin.H{"error": "Не удалось открыть файл"})
		return
	}
	defer f.Close()

	xl, err := excelize.OpenReader(f)
	if err != nil {
		logWarn(c, "Импорт товаров: не удалось разобрать Excel-файл", "filename", fileHeader.Filename, "error", err.Error())
		c.JSON(400, gin.H{"error": "Не удалось прочитать Excel-файл. Поддерживается только формат .xlsx"})
		return
	}
	defer xl.Close()

	sheet := xl.GetSheetName(0)
	if sheet == "" {
		c.JSON(400, gin.H{"error": "В файле нет листов с данными"})
		return
	}

	rows, err := xl.GetRows(sheet)
	if err != nil {
		logErr(c, err, "Импорт товаров: не удалось прочитать строки листа", "sheet", sheet)
		c.JSON(400, gin.H{"error": "Не удалось прочитать строки файла"})
		return
	}

	result := domain.ProductImportResult{}
	ctx := context.Background()

	for i, row := range rows {
		rowNum := i + 1
		if i == 0 {
			// Первая строка — заголовки, пропускаем.
			continue
		}
		// Пропускаем полностью пустые строки.
		isEmpty := true
		for _, cell := range row {
			if strings.TrimSpace(cell) != "" {
				isEmpty = false
				break
			}
		}
		if isEmpty {
			continue
		}

		get := func(idx int) string {
			if idx < len(row) {
				return row[idx]
			}
			return ""
		}

		name := strings.TrimSpace(get(0))
		barcode := strings.TrimSpace(get(1))

		if name == "" {
			result.Errors = append(result.Errors, domain.ProductImportError{
				Row: rowNum, Message: "Ячейкаи 'Ном' холи аст, номи махсулотро нависед",
			})
			continue
		}

		buyPrice, err := parseImportFloat(get(2))
		if err != nil {
			result.Errors = append(result.Errors, domain.ProductImportError{Row: rowNum, Message: "Неверная цена закупки: " + get(2)})
			continue
		}
		sellPrice, err := parseImportFloat(get(3))
		if err != nil {
			result.Errors = append(result.Errors, domain.ProductImportError{Row: rowNum, Message: "Неверная цена продажи: " + get(3)})
			continue
		}
		stock, err := parseImportFloat(get(4))
		if err != nil {
			result.Errors = append(result.Errors, domain.ProductImportError{Row: rowNum, Message: "Неверный остаток: " + get(4)})
			continue
		}
		unit, err := normalizeUnit(get(5))
		if err != nil {
			result.Errors = append(result.Errors, domain.ProductImportError{Row: rowNum, Message: err.Error()})
			continue
		}

		p := domain.Product{
			CompanyID: companyID,
			ShopID:    shopID,
			Name:      name,
			Barcode:   &barcode,
			BuyPrice:  buyPrice,
			SellPrice: sellPrice,
			Stock:     stock,
			Unit:      unit,
		}

		extraUnits, err := parseExtraUnitColumns(row)
		if err != nil {
			result.Errors = append(result.Errors, domain.ProductImportError{Row: rowNum, Message: err.Error()})
			continue
		}

		created, err := h.productRepo.UpsertFromImport(ctx, p, extraUnits)
		if err != nil {
			logErr(c, err, "Импорт товаров: ошибка сохранения строки", "row", rowNum, "barcode", barcode)
			result.Errors = append(result.Errors, domain.ProductImportError{Row: rowNum, Message: "Ошибка сохранения товара: " + err.Error()})
			continue
		}
		if created {
			result.Created++
		} else {
			result.Updated++
		}
	}

	c.JSON(http.StatusOK, result)
}

// generateBarcode — GET /api/products/generate-barcode
// Возвращает свежий, ещё никем не занятый в рамках компании внутренний
// EAN-13 штрихкод (см. domain.GenerateInternalEAN13). Ничего не сохраняет —
// это просто предложение конкретного значения, которое клиент показывает
// продавцу и заполняет им поле "Штрихкод" перед сохранением товара; сам
// товар создаётся обычным POST /api/products как и раньше. Коллизия при
// сохранении (если код неудачно совпал) по-прежнему ловится constraint'ом
// БД и обрабатывается как обычный 409, так что гонка безопасна.
func (h *Handler) generateBarcode(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)

	const maxAttempts = 10
	for i := 0; i < maxAttempts; i++ {
		candidate, err := domain.GenerateInternalEAN13()
		if err != nil {
			logErr(c, err, "Генерация штрихкода: ошибка генератора")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Не удалось сгенерировать штрихкод"})
			return
		}
		exists, err := h.productRepo.BarcodeExists(context.Background(), companyID, candidate)
		if err != nil {
			logErr(c, err, "Генерация штрихкода: ошибка проверки уникальности", "company_id", companyID)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Не удалось сгенерировать штрихкод"})
			return
		}
		if !exists {
			c.JSON(http.StatusOK, gin.H{"barcode": candidate})
			return
		}
	}
	// Крайне маловероятно (10 подряд случайных 10-значных коллизий), но
	// честно сообщаем об этом, а не отдаём заведомо занятый код.
	logWarn(c, "Генерация штрихкода: не удалось подобрать свободный код", "company_id", companyID, "attempts", maxAttempts)
	c.JSON(http.StatusInternalServerError, gin.H{"error": "Не удалось подобрать свободный штрихкод, попробуйте ещё раз"})
}

func (h *Handler) getProductByBarcode(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	barcode := c.Param("barcode")

	// Штрихкод может принадлежать как самому товару (старое поведение,
	// сохранено для обратной совместимости), так и конкретной единице
	// продажи (product_units.barcode) — например, штрихкод на упаковке.
	// Сначала пробуем товар напрямую, затем — единицу продажи.
	p, err := h.productRepo.GetByBarcode(context.Background(), companyID, shopID, barcode)
	if err != nil {
		p, err = h.productRepo.GetByUnitBarcode(context.Background(), companyID, shopID, barcode)
		if err != nil {
			logWarn(c, "Товар по штрихкоду не найден", "company_id", companyID, "barcode", barcode, "error", err.Error())
			c.JSON(http.StatusNotFound, gin.H{"error": "Товар не найден"})
			return
		}
	}

	h.attachUnits(c, companyID, []domain.Product{*p})
	c.JSON(http.StatusOK, p)
}

func (h *Handler) searchProducts(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	name := strings.TrimSpace(c.Query("q"))
	if name == "" {
		c.JSON(http.StatusOK, []domain.Product{})
		return
	}

	products, err := h.productRepo.SearchByName(context.Background(), companyID, shopID, name)
	if err != nil {
		logErr(c, err, "Ошибка поиска товаров по названию", "company_id", companyID, "query", name)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Ошибка поиска"})
		return
	}

	// Экран быстрого поиска кассира должен сразу показать карточки всех
	// единиц продажи (шт/упаковка/блок) с ценой и штрихкодом каждой — без
	// арифметики в уме у кассира и без отдельного round-trip на каждый товар.
	h.attachUnits(c, companyID, products)

	c.JSON(http.StatusOK, products)
}

// attachUnits — пакетно подгружает units для списка товаров и проставляет
// их в p.Units. Ошибка подгрузки не должна ронять весь ответ поиска —
// логируем и отдаём товары без units, чем ломаем экран кассира целиком.
func (h *Handler) attachUnits(c *gin.Context, companyID int, products []domain.Product) {
	if len(products) == 0 {
		return
	}
	ids := make([]int, len(products))
	for i, p := range products {
		ids[i] = p.ID
	}
	unitsByProduct, err := h.productUnitRepo.GetForProducts(context.Background(), companyID, ids)
	if err != nil {
		logErr(c, err, "Ошибка подгрузки единиц продажи для списка товаров", "company_id", companyID)
		return
	}
	for i := range products {
		products[i].Units = unitsByProduct[products[i].ID]
	}
}

// getAllProducts — GET /api/products?page=1&limit=50
// Возвращает страницу товаров. Параметры: page (с 1), limit (макс. 200).
func (h *Handler) getAllProducts(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)

	page, limit := parsePagination(c, 50, 200)
	offset := (page - 1) * limit

	products, total, err := h.productRepo.GetAll(context.Background(), companyID, shopID, limit, offset)
	if err != nil {
		logErr(c, err, "Ошибка получения списка товаров", "company_id", companyID)
		c.JSON(500, gin.H{"error": "Ошибка получения товаров"})
		return
	}

	// Без этого products[i].Units остаётся пустым, и клиент откатывается на
	// синтетическую единицу продажи (id = 0), которой нет в product_units —
	// оформление продажи по ней падает с "единица продажи не найдена: 0".
	h.attachUnits(c, companyID, products)

	c.JSON(200, buildPage(products, total, page, limit))
}
func (h *Handler) createProduct(c *gin.Context) {
	var p domain.Product
	if err := c.ShouldBindJSON(&p); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	if p.Barcode != nil && strings.TrimSpace(*p.Barcode) == "" {
		p.Barcode = nil
	}

	unit, err := normalizeUnit(p.Unit)
	if err != nil {
		logWarn(c, "Создание товара: неверная единица измерения", "raw_unit", p.Unit, "error", err.Error())
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	p.Unit = unit

	p.CompanyID = c.MustGet("company_id").(int)
	p.ShopID = c.MustGet("shop_id").(int)
	productID, err := h.productRepo.Create(context.Background(), p)
	if err != nil {
		logErr(c, err, "Ошибка создания товара", "company_id", p.CompanyID, "barcode", p.Barcode)
		c.JSON(500, gin.H{"error": "Ошибка создания товара"})
		return
	}
	// id нужен клиенту сразу же, чтобы он мог одним заходом добавить
	// дополнительные единицы продажи (упаковка/блок...) тому же товару,
	// не заставляя продавца заново искать только что созданный товар.
	c.JSON(200, gin.H{"status": "ok", "id": productID})
}

func (h *Handler) updateInventory(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	role, _ := c.Get("role")
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	userID, _ := c.Get("user_id")

	var input struct {
		AddStock  float64 `json:"add_stock"`
		SellPrice float64 `json:"sell_price"`
		BuyPrice  float64 `json:"buy_price"`
		Reason    string  `json:"reason"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(400, gin.H{"error": "Неверный формат данных"})
		return
	}

	isSeller := role == "seller"
	if isSeller && strings.TrimSpace(input.Reason) == "" {
		c.JSON(400, gin.H{"error": "Укажите причину изменения склада"})
		return
	}

	if err := h.productRepo.UpdateInventory(context.Background(), id, companyID, shopID, input.AddStock, input.SellPrice, input.BuyPrice); err != nil {
		if err == repository.ErrNotFound {
			logWarn(c, "Обновление склада: товар не найден", "product_id", id, "company_id", companyID)
			c.JSON(404, gin.H{"error": "Товар не найден"})
			return
		}
		if err == repository.ErrInsufficientStock {
			logWarn(c, "Обновление склада: недостаточно товара для уменьшения", "product_id", id, "company_id", companyID, "add_stock", input.AddStock)
			c.JSON(409, gin.H{"error": "Миқдор дар анбор кофӣ нест"})
			return
		}
		logErr(c, err, "Ошибка обновления склада товара", "product_id", id, "company_id", companyID)
		c.JSON(500, gin.H{"error": "Не удалось обновить склад"})
		return
	}

	if isSeller && h.tgBot != nil {
		go func() {
			ctx := context.Background()
			productName, err := h.productRepo.GetNameByID(ctx, id, companyID, shopID)
			if err != nil {
				return
			}
			ownerChatID, err := h.userRepo.GetOwnerChatID(ctx, companyID)
			if err != nil || ownerChatID == 0 {
				return
			}
			seller, _ := h.userRepo.GetByID(ctx, userID.(int))
			h.tgBot.SendInventoryChangeNotification(ownerChatID, seller.Username, productName, input.AddStock, input.Reason)
		}()
	}

	c.JSON(200, gin.H{"status": "ok"})
}

func (h *Handler) deleteProduct(c *gin.Context) {
	role := c.MustGet("role").(string)
	if role != "owner" {
		c.JSON(403, gin.H{"error": "Нет прав"})
		return
	}
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	id, _ := strconv.Atoi(c.Param("id"))
	if err := h.productRepo.SoftDelete(context.Background(), id, companyID, shopID); err != nil {
		if err == repository.ErrNotFound {
			logWarn(c, "Удаление товара: товар не найден", "product_id", id, "company_id", companyID)
			c.JSON(404, gin.H{"error": "Товар не найден"})
			return
		}
		logErr(c, err, "Ошибка удаления товара", "product_id", id, "company_id", companyID)
		c.JSON(500, gin.H{"error": "Ошибка удаления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
