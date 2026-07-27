package domain

// ProductUnit — единица продажи товара (штука, упаковка, блок, коробка...).
//
// Важно: price задаётся НЕЗАВИСИМО от цены других единиц того же товара —
// никогда не вычисляется как price_base * conversion_factor, потому что на
// практике поштучная цена иногда даже выше цены за упаковку.
//
// Barcode — nullable и принадлежит именно единице продажи, а не товару в
// целом. Это специально сделано так ради будущей автогенерации штрихкодов:
// она просто проходит по product_units WHERE barcode IS NULL и присваивает
// код, не заботясь о том, штука это или упаковка.
type ProductUnit struct {
	ID               int      `json:"id"`
	CompanyID        int      `json:"company_id"`
	ProductID        int      `json:"product_id"`
	Label            string   `json:"label"`             // "шт", "упаковка", "блок"
	ConversionFactor float64  `json:"conversion_factor"` // сколько базовых единиц (шт) в этой единице
	Price            float64  `json:"price"`
	Barcode          *string  `json:"barcode"`
	IsBase           bool     `json:"is_base"` // true = базовая "штучная" единица, создаётся автоматически
	IsActive         bool     `json:"is_active"`
}

// CreateProductUnitRequest — тело запроса на добавление/редактирование единицы продажи.
type CreateProductUnitRequest struct {
	Label            string  `json:"label" binding:"required"`
	ConversionFactor float64 `json:"conversion_factor" binding:"required,gt=0"`
	Price            float64 `json:"price" binding:"required,gte=0"`
	Barcode          *string `json:"barcode"`
}
