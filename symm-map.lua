------------------------------------------------------------------------------
--	FILE:	 Oval.lua
--	AUTHOR:  Bob Thomas (based on a concept by Brian Wade)
--	PURPOSE: Global map script - Creates an oval-shaped Pangaea.
------------------------------------------------------------------------------
--	Copyright (c) 2010 Firaxis Games, Inc. All rights reserved.
------------------------------------------------------------------------------

include("MapGenerator");
include("MultilayeredFractal");
include("FeatureGenerator");
include("TerrainGenerator");
include("FLuaVector.lua")

local debugmode = true;

function GenerateMap()

	nextRiverID = 0;
	_rivers = {};

	-- Set land, water, hills and mountains
	GeneratePlotTypes();
	-- Set terrain i.e. snow, tundra, desert, grassland, plains
	GenerateTerrain();	
	-- Rotate the map so that it is 6-way symmetrical
	applySixWaySymmetry();
	-- Determine the grouped areas for the symmetrical layout
	Map.RecalculateAreas();
	-- Add rivers symmetrically
	CustomAddRivers();
	-- Add forest, jungle, marsh, oasis, flood plains. Remove all ice.
	-- This needs to be done after rivers for correct feature placement
	AddFeatures();
	-- Place players symmetrically and add resources and natural wonders around them
	StartPlotSystem();
	-- Add barbarian camps
	numBarbCamps = AddBarbCamps();
	-- Add ruins
	AddGoodies();
	print("Added goodies");
	-- Apply symmetry again to copy features, resources, barb camps, ruins and NWs
	applySixWaySymmetry();
	-- Postprocess any oddities
	postProcessMap();
	print("Map script completed");
	
end
------------------------------------------------------------------------------
function GetMapScriptInfo()
	local world_age, temperature, rainfall, sea_level, resources = GetCoreMapOptions()
	return {
		Name = "AC10_6WAY_SYMMETRY_v0_7",
		Description = "Designed for 6FFA, this map has 6-way rotational symmetry.",
		IsAdvancedMap = false,
		IconIndex = 15,
		SortIndex = 2,
		CustomOptions = {
							world_age,		--1
							temperature,	--2
							rainfall,		--3
							sea_level,		--4
							resources,		--5
							{				--6
							Name = "El Dorado",
							Values = {
							{"ON","El Dorado can appear."},
							{"Off","No El Dorado on the map."},
							},
							DefaultValue = 2,
							SortPriority = 9,
							},
						},
	}
end
------------------------------------------------------------------------------

------------------------------------------------------------------------------
function GetMapInitData(worldSize)
	-- This function can reset map grid sizes or world wrap settings.
	--
	local worldsizes = {
		[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {24, 24},
		[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {32, 32},
		[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {40, 40},
		[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {52, 52},
		[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {64, 64},
		[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {84, 84}
		}
	local grid_size = worldsizes[worldSize];
	--
	local world = GameInfo.Worlds[worldSize];
	if(world ~= nil) then
	return {
		Width = grid_size[1],
		Height = grid_size[2],
		WrapX = true,
	};      
     end
end
------------------------------------------------------------------------------

------------------------------------------------------------------------------
function MultilayeredFractal:GeneratePlotsByRegion()
	-- Sirian's MultilayeredFractal controlling function.
	-- You -MUST- customize this function for each script using MultilayeredFractal.
	--
	-- This implementation is specific to Oval.
	local iW, iH = Map.GetGridSize();
	local fracFlags = {FRAC_POLAR = true};

	local sea_level = Map.GetCustomOption(4)
	if sea_level == 4 then
		sea_level = 1 + Map.Rand(3, "Random Sea Level - Lua");
	end
	local world_age = Map.GetCustomOption(1)
	if world_age == 4 then
		world_age = 1 + Map.Rand(3, "Random World Age - Lua");
	end
	local axis_list = {0.81, 0.75, 0.69};
	local axis_multiplier = axis_list[sea_level];
	local cohesion_list = {0.41, 0.38, 0.35};
	local cohesion_multiplier = cohesion_list[sea_level];

	-- Fill all rows with water plots.
	self.wholeworldPlotTypes = table.fill(PlotTypes.PLOT_OCEAN, iW * iH);

	-- Add the main oval as land plots.
	local centerX = math.floor(iW / 2) -1;
	local centerY = math.floor(iH / 2) -1;

	local majorAxis = centerX * axis_multiplier;
	local minorAxis = centerY * axis_multiplier;
	local majorAxisSquared = majorAxis * majorAxis;
	local minorAxisSquared = minorAxis * minorAxis;
	for x = 0, iW - 1 do
		for y = 0, iH - 1 do
			local deltaX = x - centerX;
			local deltaY = y - centerY;
			local deltaXSquared = deltaX * deltaX;
			local deltaYSquared = deltaY * deltaY;
			local d = deltaXSquared/majorAxisSquared + deltaYSquared/minorAxisSquared;
			if d <= 1 then
				local i = y * iW + x + 1;
				self.wholeworldPlotTypes[i] = PlotTypes.PLOT_LAND;				
			end
		end
	end
	-- Now add bays, fjords, inland seas, etc, but not inside the cohesion area.
	local baysFrac = Fractal.Create(iW, iH, 3, fracFlags, -1, -1);
	local iBaysThreshold = baysFrac:GetHeight(82);
	local centerX = iW / 2;
	local centerY = iH / 2;
	local majorAxis = centerX * cohesion_multiplier;
	local minorAxis = centerY * cohesion_multiplier;
	local majorAxisSquared = majorAxis * majorAxis;
	local minorAxisSquared = minorAxis * minorAxis;
	for y = 0, iH - 1 do
		for x = 0, iW - 1 do
			local deltaX = x - centerX;
			local deltaY = y - centerY;
			local deltaXSquared = deltaX * deltaX;
			local deltaYSquared = deltaY * deltaY;
			local d = deltaXSquared/majorAxisSquared + deltaYSquared/minorAxisSquared;
			if d > 1 then
				local i = y * iW + x + 1;
				local baysVal = baysFrac:GetHeight(x, y);
				if baysVal >= iBaysThreshold then
					self.wholeworldPlotTypes[i] = PlotTypes.PLOT_OCEAN;
				end
			end
		end
	end
	
	-- Land and water are set. Now apply hills and mountains.
	local args = {
		adjust_plates = 1.5,
		world_age = world_age,
	};
	self:ApplyTectonics(args)

	-- Plot Type generation completed. Return global plot array.
	return self.wholeworldPlotTypes
end
------------------------------------------------------------------------------
function GeneratePlotTypes()
	print("Setting Plot Types (Lua Oval) ...");

	local layered_world = MultilayeredFractal.Create();
	local plot_list = layered_world:GeneratePlotsByRegion();
	
	SetPlotTypes(plot_list);

	CustomGenerateCoasts();
end
------------------------------------------------------------------------------

------------------------------------------------------------------------------
function GenerateTerrain()
	print("Adding Terrain (Lua Oval) ...");
	
	-- Get Temperature setting input by user.
	local temp = Map.GetCustomOption(2)
	if temp == 4 then
		temp = 1 + Map.Rand(3, "Random Temperature - Lua");
	end

	local args = {temperature = temp};
	local terraingen = TerrainGenerator.Create(args);

	terrainTypes = terraingen:GenerateTerrain();
	
	SetTerrainTypes(terrainTypes);
end
------------------------------------------------------------------------------
function AddFeatures()
	print("Adding Features (Lua Oval) ...");

	-- Get Rainfall setting input by user.
	local rain = Map.GetCustomOption(3)
	if rain == 4 then
		rain = 1 + Map.Rand(3, "Random Rainfall - Lua");
	end
	
	local args = {rainfall = rain}
	local featuregen = FeatureGenerator.Create(args);

	-- False parameter removes mountains from coastlines.
	featuregen:AddFeatures(false);
	
	-- Remove ice from this map
	local iW, iH = Map.GetGridSize()
	for x = 0, iW -1 do
		for y = 0, iH -1 do
			local plot = Map.GetPlot(x, y);
			local featureType = plot:GetFeatureType();
			if featureType == 0 then --ice
				plot:SetFeatureType(-1); -- no feature
			end
		end
	end
end
------------------------------------------------------------------------------
function StartPlotSystem()
	local iW, iH = Map.GetGridSize();
	local centerX = math.floor(iW / 2) -1;
	local centerY = math.floor(iW / 2) -1;
	
	-- Get Resources setting input by user.
	local res = Map.GetCustomOption(5)
	if res == 6 then
		res = 1 + Map.Rand(3, "Random Resources Option - Lua");
	end

	print("Creating start plot database.");
	local start_plot_database = AssignStartingPlots.Create()
	
	print("Dividing the map in to Regions.");
	-- Regional Division Method 1: Biggest Landmass
	local args = {
		method = 1,
		resources = res,
		};
	start_plot_database:GenerateRegions(args)

	print("Choosing start locations for civilizations.");
	start_plot_database:ChooseLocations()
	
	print("Normalizing start locations and assigning them to Players.");
	start_plot_database:BalanceAndAssign()

	print("Placing Natural Wonders.");
	start_plot_database:PlaceNaturalWonders()

	print("Placing Resources and City States.");
	start_plot_database:PlaceResourcesAndCityStates()
	
	-- Check player 1 start position	
	
	--Ensure it isn't at the centre of the map - players will start too close
	count = 0;
	local player1;
	local player1startingplot;
	local plotX;
	local plotY;
	repeat
		player1 = Players[count];
		player1startingplot = player1:GetStartingPlot();
		plotX = player1startingplot:GetX();
		plotY = player1startingplot:GetY();
	until Map.PlotDistance(plotX, plotY, centerX, centerY) >= 5	
	
	--Ensure start position is on land
	NewLandPlayerStartPlot = player1startingplot:GetNearestLandPlot(); -- move to nearest land plot
	player1:SetStartingPlot(NewLandPlayerStartPlot);
		
	-- Mirror other players
	for i = 1,5 do
		local player = Players[i];
		local newstartplot = getMirroredPlot(NewLandPlayerStartPlot, i);
		player:SetStartingPlot(newstartplot);		
	end	
	
	-- Place the city states in new positions
	placeCS();
	

	
	
end
------------------------------------------------------------------------------
function HexRotate(x,y)
	-- Take hex x and y coordinates and rotate them 60 degrees clockwise
	return (x+y), -x
end

function RotateRight(x,y, rotations)
	-- Take x and y coordinates and return them rotated in increments of 60 degrees around the centre of the map
	local iW, iH = Map.GetGridSize()
	
	local centerX = math.floor(iW / 2) -1;
	local centerY = math.floor(iH / 2) -1;
	local centerhexCoords = ToHexFromGrid(Vector2(centerX, centerY));
	
	local hexCoords = ToHexFromGrid(Vector2(x,y));
	local locX = hexCoords.x - centerhexCoords.x;
	local locY = hexCoords.y - centerhexCoords.y;
	
	for i = 1,rotations do
		locX, locY = HexRotate(locX, locY);
	end
	
	local newX, newY = ToGridFromHex(locX + centerhexCoords.x, locY + centerhexCoords.y);
	
	if debugmode then
		--print("Mirror plot is at ", newX, newY);
	end
	
	return newX, newY
end

function getMirroredPlot(p, rotations)
  if debugmode then
    --print("Getting mirror plot")
  end
	return Map.GetPlot(RotateRight(p:GetX(), p:GetY(), rotations))
end


function applySixWaySymmetry()

  if debugmode then
    print("Applying symmetry")
  end
  
	-- Take the generated sextant and copy it to the other five
	local iW, iH = Map.GetGridSize()
	local centerX = math.floor(iW / 2) -1;
	local centerY = math.floor(iW / 2) -1;
	local centerhexCoords = ToHexFromGrid(Vector2(centerX, centerY));
	
	for x = 0, iW - 1 do
		for y = 0, iH - 1 do
			local plot = Map.GetPlot(x, y);
			local plotArea = plot:GetArea();
			local plotType = plot:GetPlotType();
			local terrainType = plot:GetTerrainType();
			local featureType = plot:GetFeatureType();
			local improvementType = plot:GetImprovementType();
			local resourceType = plot:GetResourceType(-1);
			local plotNumResource = plot:GetNumResource();
			--print("Successfully defined plot attributes")
			
						
			for i = 1,5 do
				local mirrorPlot = getMirroredPlot(plot, i);
				--print("Successfully calculated mirror plot")
				
				if mirrorPlot == nil then --out of bounds
				-- do nothing
				else				
					mirrorPlot:SetArea(plotArea);
					--print("Mirror plot area set")
					mirrorPlot:SetPlotType(plotType,false,false);
					--print("Mirror plot type set")
					mirrorPlot:SetTerrainType(terrainType,false,false);
					--print("Mirror plot terrain set")
					mirrorPlot:SetFeatureType(featureType);
					--print("Mirror plot feature set")
					mirrorPlot:SetResourceType(resourceType,plotNumResource);
					--print("Mirror plot resource set")
					mirrorPlot:SetImprovementType(improvementType);
					--print("Mirror plot improvement set")
					--print("Successfully mirrored plot")
				end
			end			
			
		end
	end
	print("Symmetry applied");	
end


function CustomGenerateCoasts()

	local shallowWater = GameDefines.SHALLOW_WATER_TERRAIN;
	local deepWater = GameDefines.DEEP_WATER_TERRAIN;

	for i, plot in Plots() do
		if(plot:IsWater()) then
			if(plot:IsAdjacentToLand()) then
				plot:SetTerrainType(shallowWater, false, false);
			else
				plot:SetTerrainType(deepWater, false, false);
			end
		end
	end
	
end

function CustomAddRivers()
	
	print("Map Generation - Adding Rivers");
	
	local passConditions = {
		function(plot)
			return plot:IsHills() or plot:IsMountain();
		end,
		
		function(plot)
			return (not plot:IsCoastalLand()) and (Map.Rand(8, "MapGenerator AddRivers") == 0);
		end,
		
		function(plot)
			local area = plot:Area();
			local plotsPerRiverEdge = GameDefines["PLOTS_PER_RIVER_EDGE"];
			return (plot:IsHills() or plot:IsMountain()) and (area:GetNumRiverEdges() <	((area:GetNumTiles() / plotsPerRiverEdge) + 1));
		end,
		
		function(plot)
			local area = plot:Area();
			local plotsPerRiverEdge = GameDefines["PLOTS_PER_RIVER_EDGE"];
			return (area:GetNumRiverEdges() < (area:GetNumTiles() / plotsPerRiverEdge) + 1);
		end
	}
	
	for iPass, passCondition in ipairs(passConditions) do
		
		local riverSourceRange;
		local seaWaterRange;
			
		if (iPass <= 2) then
			riverSourceRange = GameDefines["RIVER_SOURCE_MIN_RIVER_RANGE"];
			seaWaterRange = GameDefines["RIVER_SOURCE_MIN_SEAWATER_RANGE"];
		else
			riverSourceRange = (GameDefines["RIVER_SOURCE_MIN_RIVER_RANGE"] / 2);
			seaWaterRange = (GameDefines["RIVER_SOURCE_MIN_SEAWATER_RANGE"] / 2);
		end
			
		for i, plot in Plots() do 
			if(not plot:IsWater()) then
				if(passCondition(plot)) then
					if (not Map.FindWater(plot, riverSourceRange, true)) then
						if (not Map.FindWater(plot, seaWaterRange, false)) then
							local inlandCorner = plot:GetInlandCorner();
							if(inlandCorner) then								
								CustomDoRiver(inlandCorner);								
							end
						end
					end
				end			
			end
		end
	end	
end

function CustomDoRiver(startPlot, thisFlowDirection, originalFlowDirection, riverID)

	thisFlowDirection = thisFlowDirection or FlowDirectionTypes.NO_FLOWDIRECTION;
	originalFlowDirection = originalFlowDirection or FlowDirectionTypes.NO_FLOWDIRECTION;

	-- pStartPlot = the plot at whose SE corner the river is starting
	if (riverID == nil) then
		riverID = nextRiverID;
		nextRiverID = nextRiverID + 1;
	end
		
	local otherRiverID = _rivers[startPlot]
	if (otherRiverID ~= nil and otherRiverID ~= riverID and originalFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION) then
		print("Another river exists - returning");
		return; -- Another river already exists here; can't branch off of an existing river!
	end

	local riverPlot;
	
	local bestFlowDirection = FlowDirectionTypes.NO_FLOWDIRECTION;
	if (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTH) then
	
		riverPlot = startPlot;
		local adjacentPlot = Map.PlotDirection(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_EAST);
		if ( adjacentPlot == nil or riverPlot:IsWOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater() ) then
			print("Failed tests - returning");
			return;
		end
		
		_rivers[riverPlot] = riverID;
		riverPlot:SetWOfRiver(true, thisFlowDirection);
		---[[
		for i = 1,5 do
			local mirrorPlot = getMirroredPlot(riverPlot, i);
			_rivers[mirrorPlot] = riverID;
			mirrorFlowDirection = TurnRightFlowDirections[((thisFlowDirection+i-1)%6)];
			if i == 1 then
				mirrorPlot:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 2 then
				mirrorPlot:SetNEOfRiver(true, mirrorFlowDirection);
			elseif i == 3 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_WEST);
				mirrorPlot2:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 4 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHWEST);
				mirrorPlot2:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 5 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
				mirrorPlot2:SetNEOfRiver(true, mirrorFlowDirection);
			end				
		end
		--]]		
		riverPlot = Map.PlotDirection(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
		
	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTHEAST) then
	
		riverPlot = startPlot;
		local adjacentPlot = Map.PlotDirection(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_SOUTHEAST);
		if ( adjacentPlot == nil or riverPlot:IsNWOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater() ) then
			print("Failed tests - returning");
			return;
		end

		_rivers[riverPlot] = riverID;
		riverPlot:SetNWOfRiver(true, thisFlowDirection);
		---[[
		for i = 1,5 do
			local mirrorPlot = getMirroredPlot(riverPlot, i);
			_rivers[mirrorPlot] = riverID;
			mirrorFlowDirection = TurnRightFlowDirections[((thisFlowDirection+i-1)%6)];
			if i == 5 then
				mirrorPlot:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 1 then
				mirrorPlot:SetNEOfRiver(true, mirrorFlowDirection);
			elseif i == 2 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_WEST);
				mirrorPlot2:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 3 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHWEST);
				mirrorPlot2:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 4 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
				mirrorPlot2:SetNEOfRiver(true, mirrorFlowDirection);
			end				
		end		
		--]]
		-- riverPlot does not change
	
	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST) then
	
		riverPlot = Map.PlotDirection(startPlot:GetX(), startPlot:GetY(), DirectionTypes.DIRECTION_EAST);
		if (riverPlot == nil) then
			print("riverplot nil");
			return;
		end
		
		local adjacentPlot = Map.PlotDirection(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_SOUTHWEST);
		if (adjacentPlot == nil or riverPlot:IsNEOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater()) then
			print("Failed tests - returning");
			return;
		end

		_rivers[riverPlot] = riverID;
		riverPlot:SetNEOfRiver(true, thisFlowDirection);
		---[[
		for i = 1,5 do
			local mirrorPlot = getMirroredPlot(riverPlot, i);
			_rivers[mirrorPlot] = riverID;
			mirrorFlowDirection = TurnRightFlowDirections[((thisFlowDirection+i-1)%6)];
			if i == 4 then
				mirrorPlot:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 5 then
				mirrorPlot:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 1 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_WEST);
				mirrorPlot2:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 2 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHWEST);
				mirrorPlot2:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 3 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
				mirrorPlot2:SetNEOfRiver(true, mirrorFlowDirection);
			end			
		end
		--]]
		-- riverPlot does not change
	
	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_SOUTH) then
	
		riverPlot = Map.PlotDirection(startPlot:GetX(), startPlot:GetY(), DirectionTypes.DIRECTION_SOUTHWEST);
		if (riverPlot == nil) then
			print("riverplot nil");
			return;
		end
		
		local adjacentPlot = Map.PlotDirection(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_EAST);
		if (adjacentPlot == nil or riverPlot:IsWOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater()) then
			print("Failed tests - returning");
			return;
		end
		
		_rivers[riverPlot] = riverID;
		riverPlot:SetWOfRiver(true, thisFlowDirection);
		---[[
		for i = 1,5 do
			local mirrorPlot = getMirroredPlot(riverPlot, i);
			_rivers[mirrorPlot] = riverID;
			mirrorFlowDirection = TurnRightFlowDirections[((thisFlowDirection+i-1)%6)];
			if i == 1 then
				mirrorPlot:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 2 then
				mirrorPlot:SetNEOfRiver(true, mirrorFlowDirection);
			elseif i == 3 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_WEST);
				mirrorPlot2:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 4 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHWEST);
				mirrorPlot2:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 5 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
				mirrorPlot2:SetNEOfRiver(true, mirrorFlowDirection);
			end
		end
		--]]
		-- riverPlot does not change
	
	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST) then

		riverPlot = startPlot;
		local adjacentPlot = Map.PlotDirection(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_SOUTHEAST);
		if (adjacentPlot == nil or riverPlot:IsNWOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater()) then
			print("Failed tests - returning");
			return;
		end
		
		_rivers[riverPlot] = riverID;
		riverPlot:SetNWOfRiver(true, thisFlowDirection);
		---[[
		for i = 1,5 do
			local mirrorPlot = getMirroredPlot(riverPlot, i);
			_rivers[mirrorPlot] = riverID;
			mirrorFlowDirection = TurnRightFlowDirections[((thisFlowDirection+i-1)%6)];
			if i == 5 then
				mirrorPlot:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 1 then
				mirrorPlot:SetNEOfRiver(true, mirrorFlowDirection);
			elseif i == 2 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_WEST);
				mirrorPlot2:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 3 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHWEST);
				mirrorPlot2:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 4 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
				mirrorPlot2:SetNEOfRiver(true, mirrorFlowDirection);
			end				
		end
		--]]
		-- riverPlot does not change

	elseif (thisFlowDirection == FlowDirectionTypes.FLOWDIRECTION_NORTHWEST) then
		
		riverPlot = startPlot;
		local adjacentPlot = Map.PlotDirection(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_SOUTHWEST);
		
		if ( adjacentPlot == nil or riverPlot:IsNEOfRiver() or riverPlot:IsWater() or adjacentPlot:IsWater()) then
			print("Failed tests - returning");
			return;
		end

		_rivers[riverPlot] = riverID;
		riverPlot:SetNEOfRiver(true, thisFlowDirection);
		---[[
		for i = 1,5 do
			local mirrorPlot = getMirroredPlot(riverPlot, i);
			_rivers[mirrorPlot] = riverID;
			mirrorFlowDirection = TurnRightFlowDirections[((thisFlowDirection+i-1)%6)];
			if i == 4 then
				mirrorPlot:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 5 then
				mirrorPlot:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 1 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_WEST);
				mirrorPlot2:SetWOfRiver(true, mirrorFlowDirection);
			elseif i == 2 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHWEST);
				mirrorPlot2:SetNWOfRiver(true, mirrorFlowDirection);
			elseif i == 3 then
				local mirrorPlot2 = Map.PlotDirection(mirrorPlot:GetX(), mirrorPlot:GetY(), DirectionTypes.DIRECTION_NORTHEAST);
				mirrorPlot2:SetNEOfRiver(true, mirrorFlowDirection);
			end			
		end
		--]]
		riverPlot = Map.PlotDirection(riverPlot:GetX(), riverPlot:GetY(), DirectionTypes.DIRECTION_WEST);

	else
		
		--error("Illegal direction type"); 
		-- River is starting here, set the direction in the next step
		riverPlot = startPlot;			
	end

	if (riverPlot == nil or riverPlot:IsWater()) then
		-- The river has flowed off the edge of the map or into the ocean. All is well.
		if riverPlot == nil then
			print("riverplot nil");
		else
			print("riverplot is water");
		end
		return; 
	end

	-- Storing X,Y positions as locals to prevent redundant function calls.
	local riverPlotX = riverPlot:GetX();
	local riverPlotY = riverPlot:GetY();
	
	-- Table of methods used to determine the adjacent plot.
	local adjacentPlotFunctions = {
		[FlowDirectionTypes.FLOWDIRECTION_NORTH] = function() 
			return Map.PlotDirection(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_NORTHWEST); 
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_NORTHEAST] = function() 
			return Map.PlotDirection(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_NORTHEAST);
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST] = function() 
			return Map.PlotDirection(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_EAST);
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_SOUTH] = function() 
			return Map.PlotDirection(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_SOUTHWEST);
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST] = function() 
			return Map.PlotDirection(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_WEST);
		end,
		
		[FlowDirectionTypes.FLOWDIRECTION_NORTHWEST] = function() 
			return Map.PlotDirection(riverPlotX, riverPlotY, DirectionTypes.DIRECTION_NORTHWEST);
		end	
	}
	
	if(bestFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION) then

		-- Attempt to calculate the best flow direction.
		local bestValue = math.huge;
		for flowDirection, getAdjacentPlot in pairs(adjacentPlotFunctions) do
			
			if (GetOppositeFlowDirection(flowDirection) ~= originalFlowDirection) then
				
				if (thisFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION or
					flowDirection == TurnRightFlowDirections[thisFlowDirection] or 
					flowDirection == TurnLeftFlowDirections[thisFlowDirection]) then
				
					local adjacentPlot = getAdjacentPlot();
					
					if (adjacentPlot ~= nil) then
					
						local value = GetRiverValueAtPlot(adjacentPlot);
						if (flowDirection == originalFlowDirection) then
							value = (value * 3) / 4;
						end
						
						if (value < bestValue) then
							bestValue = value;
							bestFlowDirection = flowDirection;
						end
					end
				end
			end
		end
		
		-- Try a second pass allowing the river to "flow backwards".
		if(bestFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION) then
		
			local bestValue = math.huge;
			for flowDirection, getAdjacentPlot in pairs(adjacentPlotFunctions) do
			
				if (thisFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION or
					flowDirection == TurnRightFlowDirections[thisFlowDirection] or 
					flowDirection == TurnLeftFlowDirections[thisFlowDirection]) then
				
					local adjacentPlot = getAdjacentPlot();
					
					if (adjacentPlot ~= nil) then
						
						local value = GetRiverValueAtPlot(adjacentPlot);
						if (value < bestValue) then
							bestValue = value;
							bestFlowDirection = flowDirection;
						end
					end	
				end
			end
		end
		
	end
	
	--Recursively generate river.
	if (bestFlowDirection ~= FlowDirectionTypes.NO_FLOWDIRECTION) then
		if  (originalFlowDirection == FlowDirectionTypes.NO_FLOWDIRECTION) then
			originalFlowDirection = bestFlowDirection;
		end
		--print("Recursive call");
		CustomDoRiver(riverPlot, bestFlowDirection, originalFlowDirection, riverID);
	end
	
	
end

function AddBarbCamps()
	if (Game.IsOption(GameOptionTypes.GAMEOPTION_BARBARIANS)) then
		return false;
	end
	numCamps = 0;
	for improvement in GameInfo.Improvements() do
		local tilesPerGoody = 100;
		local improvementID = 1; --barbs id
		if(improvement.ID == 1) then
			for index, plot in Plots(Shuffle) do
				if ( not plot:IsWater() ) then
					--Prevents too many Barbs from clustering on any one landmass.
					local area = plot:Area();
					local improvementCount = area:GetNumImprovements(improvementID);
					local scaler = (area:GetNumTiles() + (tilesPerGoody/2))/tilesPerGoody;
					if (improvementCount < scaler) then
						if (improvementCanPlaceAt(improvement, plot)) then
							plot:SetImprovementType(improvementID);
							numCamps = numCamps + 1;					
						end
					end
				end
			end
		end
	end
	return numCamps;
end


function improvementCanPlaceAt(improvement, plot)
	local improvementID = improvement.ID;
	local NO_TEAM = -1;
	local NO_RESOURCE = -1;
	local NO_IMPROVEMENT = -1;
	if (not plot:CanHaveImprovement(improvementID, NO_TEAM)) then
		return false;
	end
	if (plot:GetImprovementType() ~= NO_IMPROVEMENT) then
		return false;
	end
	if (plot:GetResourceType() ~= NO_RESOURCE) then
		return false;
	end
	if (plot:IsImpassable()) then
		return false;
	end
	-- Don't allow on tiny islands.
	local areaID = plot:GetArea();
	local area = Map.GetArea(areaID);
	local numTiles = area:GetNumTiles();
	if (numTiles < 3) then
		return false;
	end
	-- Check for being too close to another of this goody type.
	local uniqueRange = improvement.GoodyRange;
	local plotX = plot:GetX();
	local plotY = plot:GetY();
	for dx = -4, 4 do
		for dy = -4, 4 do
			local otherPlot = Map.PlotXYWithRangeCheck(plotX, plotY, dx, dy, 2);
			if(otherPlot and otherPlot:GetImprovementType() == improvementID) then
				return false;
			end
			if(otherPlot and otherPlot:HasBarbarianCamp()) then
				return false;
			end
		end
	end
	-- Check for being too close to a civ start.
	for dx = -4, 4 do
		for dy = -4, 4 do
			local otherPlot = Map.PlotXYWithRangeCheck(plotX, plotY, dx, dy, 3);
			if(otherPlot) then
				if otherPlot:IsStartingPlot() then -- Loop through all ever-alive major civs, check if their start plot matches "otherPlot"
					for player_num = 0, GameDefines.MAX_CIV_PLAYERS - 1 do
						local player = Players[player_num];
						if isValidPlayer(player) then
							-- Need to compare otherPlot with this civ's start plot and return false if a match.
							local playerStartPlot = player:GetStartingPlot();
							if otherPlot == playerStartPlot then
								return false;
							end
						end
					end
				end
			end
		end
	end
	
	return true;
end

function isValidPlayer(pPlayer)
	return  pPlayer ~= nil and pPlayer:GetStartingPlot() ~= nil and pPlayer:IsAlive();
end

function postProcessMap()

	print("Beginning postprocessing");

	local iW, iH = Map.GetGridSize();

	local ElDorado_useroption = Map.GetCustomOption(6);
	local barbplayer = Players[63];
	--print("There are ", numBarbCamps," barbarian camps");

	-- Postprocess the players
	-- Add settlers
	for player_num = 0, GameDefines.MAX_CIV_PLAYERS - 1 do
		local player = Players[player_num];
		if isValidPlayer(player) then		
			local startplot = player:GetStartingPlot();
			local settler = player:InitUnit(GameInfoTypes["UNIT_SETTLER"], startplot:GetX(), startplot:GetY());		
		end	
	end

	---[[ Add starting warrior or alternate unit
	-- Add the first warrior as usual, then mirror it for other players
	local player = Players[0];
	local startplot = player:GetStartingPlot();	
	local warrior = player:InitUnit(getStartingUnitID(player), startplot:GetX(), startplot:GetY());
	warrior:JumpToNearestValidPlot();
	local warriorplot = warrior:GetPlot();
			
	for i = 1,5 do
		player = Players[i];
		local newwarriorplot = getMirroredPlot(warriorplot, i);				
		player:InitUnit(getStartingUnitID(player), newwarriorplot:GetX(), newwarriorplot:GetY());		
	end	
	--]]
	-- Postprocess the plots
	for x = 0, iW -1 do
		for y = 0, iH - 1 do
			local plot = Map.GetPlot(x,y);
			
			-- Remove El Dorado	
			if ElDorado_useroption == 2 then
				local featureType = plot:GetFeatureType();
				if featureType == 16 then -- El Dorado
					print("Removing El Dorado");
					featureType = -1; -- no feature
					plot:SetFeatureType(featureType);					
				end	
			end	

			-- Add barb defenders to all camps
			if plot:HasBarbarianCamp() then
				--print("Adding barbarian to camp");
				local unit = barbplayer:InitUnit( 85, x, y, UNITAI_DEFENSE, NO_DIRECTION); --add barb warrior (ID 85)
				--unit:JumpToNearestValidPlot();
			end
			
			
			
			
			
			
			
		end
	end

	print("Finished postprocessing");
end


function canPlaceCSAtPlot(plot, playerplot)
-- Checks if this plot or any of its mirrors are too close to the start of the specified player
-- Also checks if the plot is too close to the centre of the map, so that it will not be too close to its own mirrors
local iW, iH = Map.GetGridSize();
local centerX = math.floor(iW / 2) -1;
local centerY = math.floor(iW / 2) -1;

if Map.PlotDistance(plot:GetX(), plot:GetY(), centerX, centerY) < 4 then
	return false;
end


for i = 1,6 do
	mirrorPlot = getMirroredPlot(plot,i);

	local plotX = mirrorPlot:GetX();
	local plotY = mirrorPlot:GetY();
	for dx = -4, 4 do
		for dy = -4, 4 do
			local otherPlot = Map.PlotXYWithRangeCheck(plotX, plotY, dx, dy, 4);
			if otherPlot == playerplot then
					return false;
			end		
		end
	end

end

return true;

end

function getCSStartPlots()

local CS1StartPlot;
local CS2StartPlot;

for player_ID = GameDefines.MAX_MAJOR_CIVS, GameDefines.MAX_MAJOR_CIVS + GameDefines.MAX_MINOR_CIVS - 1 do -- all CS IDs
	local csplayer = Players[player_ID];
	if csplayer:IsEverAlive() then
		local csStartPlot = csplayer:GetStartingPlot();
		--print("CS start plot is ", csStartPlot:GetX(), csStartPlot:GetY());
		if canPlaceCSAtPlot(csStartPlot, Players[0]:GetStartingPlot()) then
			CS1StartPlot = csStartPlot;
			for player_ID2 = player_ID +1, GameDefines.MAX_MAJOR_CIVS + GameDefines.MAX_MINOR_CIVS - 1 do -- all other CS IDs
				local csplayer2 = Players[player_ID2];
				if csplayer2:IsEverAlive() then
					local csStartPlot2 = csplayer2:GetStartingPlot();
					if canPlaceCSAtPlot(csStartPlot2, Players[0]:GetStartingPlot()) then
						if canPlaceCSAtPlot(csStartPlot2, CS1StartPlot) then
							CS2StartPlot = csStartPlot2;
							return CS1StartPlot, CS2StartPlot;
						end
					end
				end
			end
		end
	end
end

end

function placeCS()

local CS1StartPlot, CS2StartPlot = getCSStartPlots();

--print("Number of start plots found = ", startPlotsFound);
if CS1StartPlot then
	print("CS1StartPlot valid");
end
if CS2StartPlot then
	print("CS2StartPlot valid");
end
	
-- Place first two CS and their mirror images
local csPlaced = 0;
for player_ID = GameDefines.MAX_MAJOR_CIVS, GameDefines.MAX_MAJOR_CIVS + GameDefines.MAX_MINOR_CIVS - 1 do -- all CS IDs
local csplayer = Players[player_ID];
	if csplayer:IsEverAlive() then
	--print(csplayer:GetName());
		if csPlaced == 0 then
			--print("csplayer is", csplayer:GetName());
			--print("CS1StartPlot is at", CS1StartPlot:GetX(), CS1StartPlot:GetY());
			csplayer:SetStartingPlot(CS1StartPlot);
			csPlaced = csPlaced + 1;
		elseif csPlaced < 6 then
			csplayer:SetStartingPlot(getMirroredPlot(CS1StartPlot, csPlaced));
			csPlaced = csPlaced + 1;
		elseif csPlaced == 6 then
			csplayer:SetStartingPlot(CS2StartPlot);
			csPlaced = csPlaced + 1;
		else
			csplayer:SetStartingPlot(getMirroredPlot(CS2StartPlot, csPlaced - 6));
			csPlaced = csPlaced + 1;
		end
	end
end

end

LuxuryCategories = {					-- currently unused
{RESOURCE_CITRUS, RESOURCE_COCOA},
{RESOURCE_CRAB, RESOURCE_WHALES},
{RESOURCE_SALT},
{RESOURCE_COPPER, RESOURCE_GOLD, RESOURCE_SILVER},
{RESOURCE_COTTON, RESOURCE_DYES, RESOURCE_INCENSE, RESOURCE_SILK, RESOURCE_SPICES, RESOURCE_SUGAR, RESOURCE_WINE},
{RESOURCE_FURS, RESOURCE_IVORY, RESOURCE_TRUFFLES},
{RESOURCE_MARBLE},
{RESOURCE_PEARLS},
{RESOURCE_GEMS}
}


function getCategory(lux)	-- currently unused

for k,v in pairs(LuxuryCategories) do

	if (type(v) == "table") then
		for _, v2 in pairs(v) do
			if v2 == lux then
				return k;
			end
		end
	elseif v == lux then
		return k;
	end

end

return nil;

end


function getLuxuryByCategory(cat)	-- currently unused

if cat == nil then
	return nil;
end

local CandidateLuxuries = LuxuryCategories[cat];

local idx = 1+ Map.Rand(#CandidateLuxuries, "Choosing a luxury by category");

return CandidateLuxuries[idx];

end


function GetGameInitialItemsOverrides()
-- Prevent initial units per player since we are placing them in this script.

local override = {};

for player_num = 0, GameDefines.MAX_CIV_PLAYERS - 1 do
	local player = Players[player_num];
	if isValidPlayer(player) then
		override[player_num] = false;
	end	
end


return {GrantInitialUnitsPerPlayer = override}

end

function getStartingUnitID(player)
local playerciv = player:GetCivilizationType();

-- Hardcoded for now - there should be a way to do this via XML?
if playerciv == GameInfo.Civilizations.CIVILIZATION_AZTEC.ID then
	return GameInfoTypes["UNIT_AZTEC_JAGUAR"];
elseif playerciv == GameInfo.Civilizations.CIVILIZATION_POLYNESIA.ID then
	return GameInfoTypes["UNIT_POLYNESIAN_MAORI_WARRIOR"];
elseif playerciv == GameInfo.Civilizations.CIVILIZATION_SHOSHONE.ID then
	return GameInfoTypes["UNIT_SHOSHONE_PATHFINDER"];
else
	return GameInfoTypes["UNIT_WARRIOR"];
end
end
