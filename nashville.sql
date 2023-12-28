--change SalesDate column into Date
ALTER TABLE nashville
ADD SaleDateConverted DATE

UPDATE nashville
SET SaleDateConverted = CONVERT(DATE, SaleDate)

ALTER TABLE nashville
DROP COLUMN SaleDate
EXEC sp_rename 'nashville.SaleDateConverted', 'SaleDate', 'COLUMN';


-- fill NULL value in PropertyAddress
UPDATE b
SET PropertyAddress = ISNULL(b.PropertyAddress, a.PropertyAddress)
FROM 
	nashville a
INNER JOIN 
	nashville b
	ON a.ParcelID =  b.ParcelID
	AND a.UniqueID <> b.UniqueID
WHERE b.PropertyAddress IS NULL

-- split PropertyAddress into Address and City
ALTER TABLE nashville
ADD PropertyCity nvarchar(255)

UPDATE nashville
SET PropertyCity = RIGHT(PropertyAddress, LEN(PropertyAddress) - CHARINDEX(',',PropertyAddress))

UPDATE nashville
SET PropertyAddress = SUBSTRING(PropertyAddress, 1, CHARINDEX(',',PropertyAddress)-1)

-- split OwnerAddress into Address, City, and State
ALTER TABLE nashville
ADD 
	OwnerCity nvarchar(255)
	, OwnerState nvarchar(255) 

UPDATE nashville
SET 
	OwnerCity = PARSENAME(REPLACE(OwnerAddress, ',', '.'), 2)
	, OwnerState = PARSENAME(REPLACE(OwnerAddress, ',', '.'), 1)

UPDATE nashville
SET OwnerAddress = PARSENAME(REPLACE(OwnerAddress, ',', '.'), 3)

--check consistency in SoldAsVacant
SELECT 
	DISTINCT(SoldAsVacant)
	, COUNT(SoldAsVacant)
FROM nashville
GROUP BY SoldAsVacant 
ORDER BY SoldAsVacant

--solidify the format of LandUse
UPDATE nashville
SET LandUse = 
	CASE 
			WHEN LandUse = 'VACANT RES LAND' THEN 'VACANT RESIDENTIAL LAND'
			WHEN LandUse = 'VACANT RESIENTIAL LAND' THEN 'VACANT RESIDENTIAL LAND'
			WHEN LandUse = 'CONDO' THEN 'RESIDENTIAL CONDO'
			WHEN LandUse LIKE 'CONDOMINIUM%' THEN 'RESIDENTIAL CONDO'
			WHEN LandUse LIKE 'GREENBELT%' THEN 'GREENBELT'
			ELSE LandUse
		END 

--solidify the format of SoldAsVacant
UPDATE nashville
SET SoldAsVacant = (
	SELECT 
	CASE 
		WHEN SoldAsVacant = 'N' THEN 'No'
		WHEN SoldAsVacant = 'Y' THEN 'Yes'
		ELSE SoldAsVacant
	END AS SoldAsVacant
	)

--remove duplicates
WITH orders AS
	(SELECT 
		ROW_NUMBER() OVER(PARTITION BY ParcelID
										, PropertyAddress
										, SalePrice
										, LegalReference
										, OwnerName
										, SaleDate
							ORDER BY ParcelID) AS orders --Select the columns that should not be similar for more than 1 item
		, *
	FROM nashville)

DELETE 
FROM orders
WHERE  orders > 1

SELECT *
FROM nashville

--BREAK THE ORIGINAL TABLE INTO SMALL TABLES
--Create owner table which contains owners'names and addresses
WITH owner_name AS
	(SELECT 
		ParcelID
		,[OwnerName]
		,[OwnerAddress]
		,[OwnerCity]
		,[OwnerState]
		, ROW_NUMBER() OVER(PARTITION BY [OwnerName], OwnerAddress ORDER BY ParcelID) AS number
	FROM nashville
	WHERE OwnerName IS NOT NULL)
, owner_parcel AS
	(SELECT 
		ParcelID
		,[OwnerName]
		,[OwnerAddress]
		,[OwnerCity]
		,[OwnerState]
		, ROW_NUMBER() OVER(PARTITION BY ParcelID ORDER BY ParcelID) AS number
	FROM nashville
	WHERE OwnerName IS NULL)
, owners AS
	(SELECT *
	FROM owner_name
	WHERE number = 1
	UNION 
	SELECT *
	FROM owner_parcel
	WHERE number = 1)

SELECT *
INTO Owner_info
FROM owners 

ALTER TABLE Owner_info DROP COLUMN number

DELETE FROM Owner_info --eliminate null values
WHERE OwnerName IS NULL
AND OwnerAddress IS NULL

SELECT *
FROM Owner_info

--Create a new table land_info which contains the information about the building
SELECT
	[UniqueID ]
	  ,[Acreage]
      ,[TaxDistrict]
      ,[LandValue]
      ,[BuildingValue]
      ,[TotalValue]
      ,[YearBuilt]
      ,[Bedrooms]
      ,[FullBath]
      ,[HalfBath]
INTO Land_info
FROM nashville

DELETE FROM Land_info --eliminate NULL values
WHERE 
	[Acreage] IS NULL
AND [TaxDistrict] IS NULL
AND [LandValue] IS NULL
AND [BuildingValue] IS NULL
AND [TotalValue] IS NULL
AND [YearBuilt] IS NULL
AND [Bedrooms] IS NULL
AND [FullBath] IS NULL  
AND [HalfBath] IS NULL

SELECT *
FROM Land_info

--Create new tables PropertyType1, PropertyType2 which contain the type of the property
CREATE TABLE PropertyType1
	( PropertyID int
	, PropertyUse nvarchar(225)
	)

CREATE TABLE PropertyType2
	( PropertyID int
	, PropertyUse nvarchar(225)
	)

INSERT INTO PropertyType1 (PropertyUse, PropertyID)
	(SELECT
		LandUse
		, ROW_NUMBER() OVER(ORDER BY LandUse) AS LandID
	FROM nashville
	GROUP BY LandUse
	HAVING COUNT(LandUse) > 100)


INSERT INTO PropertyType2 (PropertyUse, PropertyID)
	(SELECT
		LandUse
		, ROW_NUMBER() OVER(ORDER BY LandUse) AS LandID
	FROM nashville
	GROUP BY LandUse
	HAVING COUNT(LandUse) <= 100)

SELECT *
FROM PropertyType1

SELECT *
FROM PropertyType2

--Create a new Fact_Property table
SELECT [UniqueID ]
      ,[ParcelID]
      ,[LandUse] AS PropertyUse
      ,[PropertyAddress]
      ,[SalePrice]
      ,[LegalReference]
      ,[SoldAsVacant]
      ,[SaleDate]
INTO Fact_Property 
FROM [Nashville].[dbo].[nashville]

WITH newLandUse AS 
    (SELECT 
        UniqueID,
        MAX(COALESCE(t1.PropertyID, t2.PropertyID)) AS PropertyUse  -- Use an aggregate function like MAX
    FROM Fact_Property p
    LEFT JOIN PropertyType1 t1 ON p.PropertyUse = t1.PropertyUse
    LEFT JOIN PropertyType2 t2 ON p.PropertyUse = t2.PropertyUse
    GROUP BY UniqueID)  -- Group by the unique identifier

UPDATE Fact_Property
SET Fact_Property.PropertyUse = newLandUse.PropertyUse
FROM Fact_Property
INNER JOIN newLandUse 
	ON Fact_Property.UniqueID = newLandUse.UniqueID

SELECT * 
FROM Fact_Property
