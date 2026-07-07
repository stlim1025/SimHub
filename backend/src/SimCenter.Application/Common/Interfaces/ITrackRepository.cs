using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>Track 마스터 조회 포트. 게임 정수 트랙 ID → 도메인 Track 매핑.</summary>
public interface ITrackRepository
{
    Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken cancellationToken = default);
}
