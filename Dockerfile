FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS web
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git libstdc++6 python3 unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.47.4
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}" \
    CI=true
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY lib/ lib/
COPY web/ web/
COPY tool/build_cloud_web.py tool/
RUN python3 tool/build_cloud_web.py

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS api
WORKDIR /src
COPY backend/TeacherAI.Api/*.csproj backend/TeacherAI.Api/
COPY backend/TeacherAI.ServiceDefaults/*.csproj backend/TeacherAI.ServiceDefaults/
RUN dotnet restore backend/TeacherAI.Api
COPY backend/TeacherAI.Api/ backend/TeacherAI.Api/
COPY backend/TeacherAI.ServiceDefaults/ backend/TeacherAI.ServiceDefaults/
COPY --from=web /src/backend/TeacherAI.Api/wwwroot/ backend/TeacherAI.Api/wwwroot/
RUN dotnet publish backend/TeacherAI.Api -c Release --no-restore -p:UseAppHost=false -o /out

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=api /out/ ./
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "export ASPNETCORE_HTTP_PORTS=\"${PORT:-8080}\"; exec dotnet TeacherAI.Api.dll \"$@\"", "teacher-ai"]
