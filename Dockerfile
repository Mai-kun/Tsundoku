FROM node:22-alpine AS frontend
WORKDIR /app/frontend
COPY mediatracker-ui/package*.json ./
RUN npm ci
COPY mediatracker-ui/ ./
RUN npm run build

FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /app
COPY MediaTracker.Server/MediaTracker.Server.csproj MediaTracker.Server/
RUN dotnet restore MediaTracker.Server/MediaTracker.Server.csproj
COPY MediaTracker.Server/ MediaTracker.Server/
COPY --from=frontend /app/MediaTracker.Server/wwwroot/ MediaTracker.Server/wwwroot/
RUN dotnet publish MediaTracker.Server/MediaTracker.Server.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS final
WORKDIR /app
COPY --from=build /app/publish .
RUN mkdir -p /app/data/covers
ENV HEADLESS=true
ENV ASPNETCORE_URLS=http://+:5000
EXPOSE 5000
ENTRYPOINT ["dotnet", "Tsundoku.dll"]
